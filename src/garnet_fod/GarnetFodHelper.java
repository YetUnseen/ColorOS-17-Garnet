package com.garnet.fod;

import android.net.LocalSocket;
import android.net.LocalSocketAddress;
import android.os.Binder;
import android.os.IBinder;
import android.os.IInterface;
import android.os.Parcel;
import android.os.RemoteException;
import android.util.Log;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

/**
 * Bridges ColorOS optical FOD callbacks inside system_server to:
 *   1. Xiaomi vendor.xiaomi.hardware.fingerprintextension@1.0::IXiaomiFingerprint::extCmd
 *      - extCmd(4, val): FP state (0=idle, 1=auth, 3=enroll)
 *      - extCmd(1, val): gxzwAnim/FOD visible (1=show, 0=hide)
 *      Both together arm FodEngineCore TouchEnable=1 on Xiaomi HyperOS 3 mfp-daemon.
 *   2. /dev/garnet_fod.sock -> native /system/bin/garnet_lhbm_helper (/dev/mi_display/disp_feature)
 *   3. vendor.oplus.hardware.displaypanelfeature.IDisplayPanelFeature/default AIDL HAL service
 *      so SmoothTransitionController enables Panoramic / Animated AOD (feature 0xd9 -> 0x0e)
 *      and routes FOD highlight control (feature 0x1c) to Local HBM.
 */
public final class GarnetFodHelper {
    private static final String TAG = "GarnetFodHelper";
    private static final String SOCK_PATH = "/dev/garnet_fod.sock";
    private static final String XIAOMI_FP_FQNAME = "vendor.xiaomi.hardware.fingerprintextension@1.0::IXiaomiFingerprint";
    private static final String XIAOMI_FP_INSTANCE = "default";

    private static final String DISPLAY_PANEL_SVC = "vendor.oplus.hardware.displaypanelfeature.IDisplayPanelFeature/default";
    private static final String DISPLAY_PANEL_DESC = "vendor.oplus.hardware.displaypanelfeature.IDisplayPanelFeature";
    private static final String DISPLAY_PANEL_HASH = "86d5512f98a34fe15c70d7bb459d3f7e853bcde3";
    private static final int DISPLAY_PANEL_VERSION = 1;
    private static final int FEATURE_PANORAMIC_AOD = 0xd9;
    private static final int FEATURE_FOD_HIGHLIGHT = 0x1c;
    private static final int FEATURE_UDFPS_TYPE = 0xd3;
    private static final int UDFPS_TYPE_LOCAL_HBM = 0x10; // SystemUI isLocalHBM() => no global FOD dim layer
    private static final int PANORAMIC_CAP_BITS = 0x0e; // 0x2 SmoothTransition | 0x4 Panoramic | 0x8 AllDay

    private static final int CMD_GXZW_ANIM = 1;
    private static final int CMD_FP_STATE = 4;
    private static final int FP_IDLE = 0;
    private static final int FP_AUTH = 1;
    private static final int FP_ENROLL = 3;

    private static final Object LOCK = new Object();
    private static final Object PANEL_LOCK = new Object();
    private static volatile boolean sInitialized = false;
    private static volatile boolean sPanelRegistered = false;
    private static volatile DisplayPanelFeatureBinder sPanelBinder = null;
    private static volatile Object sFpBinder = null;
    private static volatile LocalSocket sSocket = null;
    private static volatile OutputStream sOut = null;
    private static volatile boolean sHbmOn = false;
    private static volatile boolean sActive = false;
    private static volatile int sFpState = FP_IDLE;

    private static Method sGetService;
    private static Constructor<?> sHwParcelCtor;
    private static Method sWriteInterfaceToken;
    private static Method sWriteInt32;
    private static Method sRelease;
    private static Method sVerifySuccess;
    private static Method sReadInt32;
    private static Method sTransact;

    private static final class DisplayPanelFeatureBinder extends Binder {
        DisplayPanelFeatureBinder() {
            try {
                Method m = Binder.class.getMethod("markVintfStability");
                m.invoke(this);
            } catch (Throwable t) {
                Log.w(TAG, "markVintfStability unavailable: " + t.getMessage());
            }
            attachInterface(new IInterface() {
                @Override
                public IBinder asBinder() {
                    return DisplayPanelFeatureBinder.this;
                }
            }, DISPLAY_PANEL_DESC);
        }

        @Override
        protected boolean onTransact(int code, Parcel data, Parcel reply, int flags) throws RemoteException {
            if (code == INTERFACE_TRANSACTION) {
                reply.writeString(DISPLAY_PANEL_DESC);
                return true;
            }
            if (code >= 1 && code <= 0xffffff) {
                data.enforceInterface(DISPLAY_PANEL_DESC);
            }
            switch (code) {
                case 0xffffff: {
                    data.enforceNoDataAvail();
                    reply.writeNoException();
                    reply.writeInt(DISPLAY_PANEL_VERSION);
                    return true;
                }
                case 0xfffffe: {
                    data.enforceNoDataAvail();
                    reply.writeNoException();
                    reply.writeString(DISPLAY_PANEL_HASH);
                    return true;
                }
                case 1: { // getDisplayPanelFeatureValue(int featureId, inout int[] result)
                    int featureId = data.readInt();
                    int outLen = data.readInt();
                    data.enforceNoDataAvail();
                    int[] out = outLen >= 0 ? new int[outLen] : null;
                    int status = -1;
                    if (featureId == FEATURE_PANORAMIC_AOD) {
                        if (out != null && out.length > 0) {
                            out[0] = PANORAMIC_CAP_BITS;
                        }
                        status = 0;
                    } else if (featureId == FEATURE_UDFPS_TYPE) {
                        if (out != null && out.length > 0) {
                            out[0] = UDFPS_TYPE_LOCAL_HBM;
                        }
                        status = 0;
                    }
                    reply.writeNoException();
                    reply.writeInt(status);
                    reply.writeIntArray(out);
                    return true;
                }
                case 2: { // setDisplayPanelFeatureValue(int featureId, in int[] values)
                    int featureId = data.readInt();
                    int[] values = data.createIntArray();
                    data.enforceNoDataAvail();
                    if (featureId == FEATURE_FOD_HIGHLIGHT) {
                        int val = (values != null && values.length > 0) ? values[0] : 0;
                        onHighLight(val);
                    }
                    reply.writeNoException();
                    reply.writeInt(0);
                    return true;
                }
                case 3: { // getDisplayPanelInfo(int infoId, inout String[] info)
                    data.readInt();
                    int outLen = data.readInt();
                    data.enforceNoDataAvail();
                    String[] out = outLen >= 0 ? new String[outLen] : null;
                    if (out != null) {
                        Arrays.fill(out, "");
                    }
                    reply.writeNoException();
                    reply.writeInt(-1);
                    reply.writeStringArray(out);
                    return true;
                }
                default:
                    return super.onTransact(code, data, reply, flags);
            }
        }
    }

    static {
        try {
            Class<?> hb = Class.forName("android.os.HwBinder");
            Class<?> ihb = Class.forName("android.os.IHwBinder");
            Class<?> hp = Class.forName("android.os.HwParcel");
            sGetService = hb.getMethod("getService", String.class, String.class);
            sHwParcelCtor = hp.getConstructor();
            sWriteInterfaceToken = hp.getMethod("writeInterfaceToken", String.class);
            sWriteInt32 = hp.getMethod("writeInt32", int.class);
            sRelease = hp.getMethod("release");
            sVerifySuccess = hp.getMethod("verifySuccess");
            sReadInt32 = hp.getMethod("readInt32");
            sTransact = ihb.getMethod("transact", int.class, hp, hp, int.class);
        } catch (Throwable t) {
            Log.e(TAG, "Failed to init HwBinder reflection", t);
        }
        try {
            ensureStarted();
            registerDisplayPanelService();
        } catch (Throwable t) {
            Log.e(TAG, "Failed to init bridge services", t);
        }
    }

    private GarnetFodHelper() {}

    public static void registerDisplayPanelService() {
        GarnetCryptoEng.register();
        if (sPanelRegistered) return;
        synchronized (PANEL_LOCK) {
            if (sPanelRegistered) return;
            try {
                if (sPanelBinder == null) {
                    sPanelBinder = new DisplayPanelFeatureBinder();
                }
                Class<?> sm = Class.forName("android.os.ServiceManager");
                Method addSvc = sm.getMethod("addService", String.class, IBinder.class);
                addSvc.invoke(null, DISPLAY_PANEL_SVC, sPanelBinder);
                sPanelRegistered = true;
                Log.i(TAG, "Registered AIDL stub service: " + DISPLAY_PANEL_SVC);
            } catch (Throwable t) {
                Log.w(TAG, "registerDisplayPanelService deferred/failed: " + t.getMessage());
            }
        }
    }

    public static void ensureStarted() {
        if (sInitialized) return;
        synchronized (LOCK) {
            if (sInitialized) return;
            sInitialized = true;
            Thread t = new Thread(new Runnable() {
                @Override
                public void run() {
                    socketLoop();
                }
            }, "GarnetFodBridge");
            t.setDaemon(true);
            t.start();
            Log.i(TAG, "GarnetFodBridge worker started");
        }
    }

    private static void socketLoop() {
        while (true) {
            registerDisplayPanelService();
            LocalSocket sock = null;
            try {
                sock = new LocalSocket();
                sock.connect(new LocalSocketAddress(SOCK_PATH, LocalSocketAddress.Namespace.FILESYSTEM));
                synchronized (LOCK) {
                    sSocket = sock;
                    sOut = sock.getOutputStream();
                }
                Log.i(TAG, "Connected to " + SOCK_PATH);
                sendLine(sActive ? "ACTIVE 1\n" : "ACTIVE 0\n");
                BufferedReader br = new BufferedReader(
                        new InputStreamReader(sock.getInputStream(), StandardCharsets.US_ASCII));
                String line;
                while ((line = br.readLine()) != null) {
                    line = line.trim();
                    if ("UI_READY 1".equals(line) || "UI_READY 0".equals(line)
                            || "TOUCH 1".equals(line) || "TOUCH 0".equals(line)) {
                        Log.d(TAG, "helper evt: " + line + " (fpState=" + sFpState + ")");
                    }
                }
            } catch (Throwable t) {
                Log.w(TAG, "Socket loop retry: " + t.getMessage());
            } finally {
                synchronized (LOCK) {
                    sOut = null;
                    sSocket = null;
                }
                if (sock != null) {
                    try { sock.close(); } catch (Throwable ignored) {}
                }
            }
            try {
                Thread.sleep(1500);
            } catch (InterruptedException ignored) {}
        }
    }

    private static Object getFpBinder() {
        Object b = sFpBinder;
        if (b != null) return b;
        try {
            if (sGetService != null) {
                b = sGetService.invoke(null, XIAOMI_FP_FQNAME, XIAOMI_FP_INSTANCE);
                sFpBinder = b;
            }
        } catch (Throwable t) {
            Log.w(TAG, "IXiaomiFingerprint getService failed: " + t.getMessage());
            sFpBinder = null;
        }
        return b;
    }

    public static int extCmd(int cmd, int param) {
        for (int attempt = 0; attempt < 2; attempt++) {
            Object binder = getFpBinder();
            if (binder == null || sHwParcelCtor == null) return -1;
            Object req = null;
            Object rep = null;
            try {
                req = sHwParcelCtor.newInstance();
                rep = sHwParcelCtor.newInstance();
                sWriteInterfaceToken.invoke(req, XIAOMI_FP_FQNAME);
                sWriteInt32.invoke(req, cmd);
                sWriteInt32.invoke(req, param);
                sTransact.invoke(binder, 1, req, rep, 0);
                sVerifySuccess.invoke(rep);
                return (Integer) sReadInt32.invoke(rep);
            } catch (Throwable t) {
                Log.w(TAG, "extCmd(" + cmd + "," + param + ") retry: " + t.getMessage());
                sFpBinder = null;
            } finally {
                try { if (req != null) sRelease.invoke(req); } catch (Throwable ignored) {}
                try { if (rep != null) sRelease.invoke(rep); } catch (Throwable ignored) {}
            }
        }
        return -1;
    }

    private static void sendLine(String line) {
        ensureStarted();
        synchronized (LOCK) {
            OutputStream os = sOut;
            if (os == null) return;
            try {
                os.write(line.getBytes(StandardCharsets.US_ASCII));
                os.flush();
            } catch (Throwable t) {
                Log.w(TAG, "sendLine failed: " + t.getMessage());
                sOut = null;
                try { if (sSocket != null) sSocket.close(); } catch (Throwable ignored) {}
                sSocket = null;
            }
        }
    }

    public static void onEnrollStart() {
        try {
            registerDisplayPanelService();
            Log.i(TAG, "onEnrollStart");
            sFpState = FP_ENROLL;
            setActive(true);
        } catch (Throwable t) {
            Log.w(TAG, "onEnrollStart err", t);
        }
    }

    public static void onAuthStart() {
        try {
            registerDisplayPanelService();
            Log.i(TAG, "onAuthStart");
            sFpState = FP_AUTH;
            setActive(true);
        } catch (Throwable t) {
            Log.w(TAG, "onAuthStart err", t);
        }
    }

    public static void onOverlayShow() {
        setActive(true);
    }

    public static void onOverlayHide() {
        setActive(false);
    }

    public static void setActive(boolean active) {
        try {
            registerDisplayPanelService();
            Log.i(TAG, "setActive(" + active + ") fpState=" + sFpState);
            if (active) {
                sActive = true;
                if (sFpState == FP_IDLE) {
                    sFpState = FP_AUTH;
                }
                extCmd(CMD_FP_STATE, sFpState);
                extCmd(CMD_GXZW_ANIM, 1);
                sendLine("ACTIVE 1\n");
            } else {
                sActive = false;
                sFpState = FP_IDLE;
                sHbmOn = false;
                sendLine("ACTIVE 0\n");
                extCmd(CMD_GXZW_ANIM, 0);
                extCmd(CMD_FP_STATE, FP_IDLE);
            }
        } catch (Throwable t) {
            Log.w(TAG, "setActive err", t);
        }
    }

    public static void onHighLight(int value) {
        if (value != 0) {
            onFingerDown();
        } else {
            onFingerUp();
        }
    }

    public static void onFingerDown() {
        try {
            Log.i(TAG, "onFingerDown");
            sHbmOn = true;
            if (sFpState == FP_IDLE || !sActive) {
                if (sFpState == FP_IDLE) {
                    sFpState = FP_AUTH;
                }
                sActive = true;
                extCmd(CMD_FP_STATE, sFpState);
                extCmd(CMD_GXZW_ANIM, 1);
                sendLine("ACTIVE 1\n");
            }
            sendLine("HBM 1\n");
        } catch (Throwable t) {
            Log.w(TAG, "onFingerDown err", t);
        }
    }

    public static void onFingerUp() {
        try {
            if (sHbmOn) {
                Log.i(TAG, "onFingerUp");
            }
            sHbmOn = false;
            sendLine("HBM 0\n");
        } catch (Throwable t) {
            Log.w(TAG, "onFingerUp err", t);
        }
    }

    public static void onAuthResult(int fingerId) {
        try {
            Log.i(TAG, "onAuthResult fingerId=" + fingerId);
            onFingerUp();
            if (fingerId != 0) {
                setActive(false);
            } else {
                sActive = true;
                if (sFpState == FP_IDLE) {
                    sFpState = FP_AUTH;
                }
                extCmd(CMD_FP_STATE, sFpState);
                extCmd(CMD_GXZW_ANIM, 1);
                sendLine("ACTIVE 1\n");
            }
        } catch (Throwable t) {
            Log.w(TAG, "onAuthResult err", t);
        }
    }

    public static void onAcquired(int acquiredInfo) {
        try {
            // Do NOT turn off LHBM on HIDL FINGERPRINT_ACQUIRED_VENDOR (6), which fpc_hal sends on UI_READY!
            if (acquiredInfo >= 0 && acquiredInfo <= 5) {
                onFingerUp();
            }
        } catch (Throwable t) {
            Log.w(TAG, "onAcquired err", t);
        }
    }
}
