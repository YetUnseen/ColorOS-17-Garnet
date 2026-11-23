package com.garnet.fod;

import android.os.Binder;
import android.os.IBinder;
import android.os.IInterface;
import android.os.Parcel;
import android.os.RemoteException;
import android.util.Log;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.lang.reflect.Method;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;

/**
 * Software stand-in for vendor.oplus.hardware.cryptoeng.ICryptoeng/default.
 *
 * The device has no cryptoeng HAL, so ColorOS Settings / SafeCenter cannot store the
 * privacy (app lock) password. This service implements only the PMS (privacy password
 * manager) commands 4001..4007 and answers null for every other command, which is what
 * callers already received when the service was missing.
 *
 * Wire format (big endian):
 *   request : int method | int 10000 | int paramNum | paramNum * (int type | int len | bytes)
 *   response: int method | int exeResult | int paramNum | paramNum * (int type | int len | bytes)
 */
final class GarnetCryptoEng {
    private static final String TAG = "GarnetCryptoEng";
    private static final String SERVICE = "vendor.oplus.hardware.cryptoeng.ICryptoeng/default";
    private static final String DESC = "vendor.oplus.hardware.cryptoeng.ICryptoeng";
    private static final String HASH = "765136eb397eb5b85ee1e089d8fec72c15e266b3";
    private static final int VERSION = 1;
    private static String sStateFile = "/data/system/garnet_pms.dat";

    private static final int M_ENROLL = 4001;
    private static final int M_VERIFY = 4002;
    private static final int M_MODIFY = 4003;
    private static final int M_DELETE = 4004;
    private static final int M_GET_INFO = 4005;
    private static final int M_ENCRYPT = 4006;
    private static final int M_RESET_ALL = 4007;

    private static final int P_PMS_TYPE = 201;
    private static final int P_PWD_INFO = 202;
    private static final int P_SECURE_INFO = 203;
    private static final int P_VERIFY_TYPE = 204;
    private static final int P_VERIFY_BUFFER = 205;
    private static final int P_CHALLENGE = 206;
    private static final int P_INFO_TYPE = 207;
    private static final int P_INFO_BUFFER = 208;
    private static final int P_HANDLER = 209;
    private static final int P_PWD_TYPE = 210;
    private static final int P_RETRY_LEFT = 211;
    private static final int P_LOCK_LEFT = 212;
    private static final int P_HIDE_EMAIL = 217;
    private static final int P_SQ_RETRY_LEFT = 219;
    private static final int P_SQ_LOCK_LEFT = 220;

    private static final int RETRY_COUNT = 5;
    private static final long CHALLENGE_TTL_MS = 10 * 60 * 1000L;
    private static final int MAX_CHALLENGES = 16;

    private static final Object LOCK = new Object();
    private static final SecureRandom RNG = new SecureRandom();
    private static volatile boolean sRegistered = false;
    private static CryptoBinder sBinder;

    private static final class Slot {
        int pwdType;
        byte[] pwdHash;
        byte[] handler;
        byte[] answerHash;
        String email = "";
        final HashMap<String, Long> challenges = new HashMap<>();
    }

    private static final Map<Integer, Slot> sSlots = new HashMap<>();
    private static boolean sLoaded = false;

    private GarnetCryptoEng() {}

    static void register() {
        if (sRegistered) return;
        synchronized (LOCK) {
            if (sRegistered) return;
            try {
                if (sBinder == null) sBinder = new CryptoBinder();
                Class<?> sm = Class.forName("android.os.ServiceManager");
                Method addSvc = sm.getMethod("addService", String.class, IBinder.class);
                addSvc.invoke(null, SERVICE, sBinder);
                sRegistered = true;
                Log.i(TAG, "Registered AIDL stub service: " + SERVICE);
            } catch (Throwable t) {
                Log.w(TAG, "register deferred/failed: " + t.getMessage());
            }
        }
    }

    private static final class CryptoBinder extends Binder {
        CryptoBinder() {
            try {
                Binder.class.getMethod("markVintfStability").invoke(this);
            } catch (Throwable t) {
                Log.w(TAG, "markVintfStability unavailable: " + t.getMessage());
            }
            attachInterface(new IInterface() {
                @Override
                public IBinder asBinder() {
                    return CryptoBinder.this;
                }
            }, DESC);
        }

        @Override
        protected boolean onTransact(int code, Parcel data, Parcel reply, int flags) throws RemoteException {
            if (code == INTERFACE_TRANSACTION) {
                reply.writeString(DESC);
                return true;
            }
            if (code >= 1 && code <= 0xffffff) {
                data.enforceInterface(DESC);
            }
            switch (code) {
                case 0xffffff:
                    data.enforceNoDataAvail();
                    reply.writeNoException();
                    reply.writeInt(VERSION);
                    return true;
                case 0xfffffe:
                    data.enforceNoDataAvail();
                    reply.writeNoException();
                    reply.writeString(HASH);
                    return true;
                case 1: {
                    byte[] in = data.createByteArray();
                    data.enforceNoDataAvail();
                    byte[] out = null;
                    try {
                        out = handle(in);
                    } catch (Throwable t) {
                        Log.w(TAG, "command failed: " + t);
                    }
                    reply.writeNoException();
                    reply.writeByteArray(out);
                    return true;
                }
                default:
                    return super.onTransact(code, data, reply, flags);
            }
        }
    }

    private static final class Params {
        final HashMap<Integer, byte[]> map = new HashMap<>();

        byte[] get(int type) {
            return map.get(type);
        }

        int getInt(int type, int def) {
            byte[] b = map.get(type);
            if (b == null || b.length != 4) return def;
            return ((b[0] & 0xff) << 24) | ((b[1] & 0xff) << 16) | ((b[2] & 0xff) << 8) | (b[3] & 0xff);
        }
    }

    private static byte[] handle(byte[] in) throws Exception {
        if (in == null || in.length < 12) return null;
        DataInputStream d = new DataInputStream(new ByteArrayInputStream(in));
        int method = d.readInt();
        if (method < M_ENROLL || method > M_RESET_ALL) return null;
        d.readInt();
        int n = d.readInt();
        Params p = new Params();
        for (int i = 0; i < n; i++) {
            if (d.available() < 8) break;
            int type = d.readInt();
            int len = d.readInt();
            if (len < 0 || len > d.available()) break;
            byte[] v = new byte[len];
            d.readFully(v);
            p.map.put(type, v);
        }
        synchronized (LOCK) {
            loadLocked();
            switch (method) {
                case M_ENROLL:
                    return enroll(p);
                case M_VERIFY:
                    return verify(p);
                case M_MODIFY:
                    return modify(p);
                case M_DELETE:
                    return delete(p);
                case M_GET_INFO:
                    return getInfo(p);
                case M_RESET_ALL:
                    sSlots.clear();
                    saveLocked();
                    return response(method, 0);
                default:
                    return response(method, 1);
            }
        }
    }

    private static Slot slot(Params p, boolean create) {
        int t = p.getInt(P_PMS_TYPE, 1);
        Slot s = sSlots.get(t);
        if (s == null && create) {
            s = new Slot();
            sSlots.put(t, s);
        }
        return s;
    }

    private static byte[] response(int method, int result, Object... kv) throws Exception {
        ByteArrayOutputStream body = new ByteArrayOutputStream();
        DataOutputStream bo = new DataOutputStream(body);
        int count = 0;
        for (int i = 0; i + 1 < kv.length; i += 2) {
            byte[] v;
            Object o = kv[i + 1];
            if (o instanceof Integer) {
                v = intBytes((Integer) o);
            } else {
                v = (byte[]) o;
            }
            if (v == null || v.length == 0) continue;
            bo.writeInt((Integer) kv[i]);
            bo.writeInt(v.length);
            bo.write(v);
            count++;
        }
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        DataOutputStream o = new DataOutputStream(out);
        o.writeInt(method);
        o.writeInt(result);
        o.writeInt(result == 0 ? count : 0);
        if (result == 0) o.write(body.toByteArray());
        return out.toByteArray();
    }

    private static byte[] intBytes(int v) {
        return new byte[] {(byte) (v >>> 24), (byte) (v >>> 16), (byte) (v >>> 8), (byte) v};
    }

    private static String hex(byte[] b) {
        StringBuilder sb = new StringBuilder();
        for (byte x : b) sb.append(String.format("%02x", x & 0xff));
        return sb.toString();
    }

    private static byte[] sha256(byte[] b) throws Exception {
        return MessageDigest.getInstance("SHA-256").digest(b);
    }

    private static byte[] newHandler() {
        byte[] h = new byte[4];
        do {
            RNG.nextBytes(h);
        } while (h[0] == 0 && h[1] == 0 && h[2] == 0 && h[3] == 0);
        return h;
    }

    private static byte[] issueChallenge(Slot s) {
        long now = System.currentTimeMillis();
        ArrayList<String> stale = new ArrayList<>();
        for (Map.Entry<String, Long> e : s.challenges.entrySet()) {
            if (now - e.getValue() > CHALLENGE_TTL_MS) stale.add(e.getKey());
        }
        for (String k : stale) s.challenges.remove(k);
        while (s.challenges.size() >= MAX_CHALLENGES) {
            String oldest = null;
            long oldestTs = Long.MAX_VALUE;
            for (Map.Entry<String, Long> e : s.challenges.entrySet()) {
                if (e.getValue() < oldestTs) {
                    oldestTs = e.getValue();
                    oldest = e.getKey();
                }
            }
            s.challenges.remove(oldest);
        }
        byte[] c = new byte[64];
        RNG.nextBytes(c);
        s.challenges.put(hex(c), now);
        return c;
    }

    private static boolean challengeValid(Slot s, byte[] c) {
        if (s == null || c == null || c.length != 64) return false;
        Long ts = s.challenges.get(hex(c));
        return ts != null && System.currentTimeMillis() - ts <= CHALLENGE_TTL_MS;
    }

    private static void parseSecureInfo(Slot s, byte[] buf) {
        // Repeated (int type | int len | 32 byte slot); 2 = answer hash, 4/10 = email halves.
        String email = "";
        for (int off = 0; off + 40 <= buf.length; off += 40) {
            int type = ((buf[off] & 0xff) << 24) | ((buf[off + 1] & 0xff) << 16)
                    | ((buf[off + 2] & 0xff) << 8) | (buf[off + 3] & 0xff);
            int len = ((buf[off + 4] & 0xff) << 24) | ((buf[off + 5] & 0xff) << 16)
                    | ((buf[off + 6] & 0xff) << 8) | (buf[off + 7] & 0xff);
            if (len < 0 || len > 32) continue;
            byte[] v = new byte[len];
            System.arraycopy(buf, off + 8, v, 0, len);
            if (type == 2) {
                byte[] a = new byte[32];
                System.arraycopy(buf, off + 8, a, 0, 32);
                s.answerHash = a;
            } else if (type == 4 || type == 10) {
                email += new String(v);
            }
        }
        s.email = email;
    }

    private static byte[] enroll(Params p) throws Exception {
        Slot existing = slot(p, false);
        byte[] pwd = p.get(P_PWD_INFO);
        int pwdType = p.getInt(P_PWD_TYPE, 0);
        if ((existing != null && existing.pwdHash != null) || pwd == null || pwd.length != 32
                || pwdType < 1 || pwdType > 5) {
            return response(M_ENROLL, 1);
        }
        Slot s = slot(p, true);
        s.pwdType = pwdType;
        s.pwdHash = pwd;
        s.handler = newHandler();
        s.answerHash = null;
        s.email = "";
        s.challenges.clear();
        byte[] sec = p.get(P_SECURE_INFO);
        if (sec != null) parseSecureInfo(s, sec);
        saveLocked();
        return response(M_ENROLL, 0, P_HANDLER, s.handler);
    }

    private static byte[] verify(Params p) throws Exception {
        Slot s = slot(p, false);
        int vt = p.getInt(P_VERIFY_TYPE, 0);
        byte[] buf = p.get(P_VERIFY_BUFFER);
        if (s == null || s.pwdHash == null || buf == null) return response(M_VERIFY, 1);
        boolean ok = false;
        if (vt == 1) {
            byte[] pre = new byte[40];
            System.arraycopy(s.pwdHash, 0, pre, 0, 32);
            System.arraycopy(s.handler, 0, pre, 32, s.handler.length);
            ok = MessageDigest.isEqual(sha256(pre), buf);
        } else if (vt == 2) {
            ok = s.answerHash != null && MessageDigest.isEqual(s.answerHash, buf);
        } else if (vt == 8) {
            ok = challengeValid(s, buf);
        }
        if (!ok) return response(M_VERIFY, 1);
        return response(M_VERIFY, 0, P_CHALLENGE, issueChallenge(s));
    }

    private static byte[] modify(Params p) throws Exception {
        Slot s = slot(p, false);
        if (s == null || s.pwdHash == null || !challengeValid(s, p.get(P_CHALLENGE))) {
            return response(M_MODIFY, 1);
        }
        int infoType = p.getInt(P_INFO_TYPE, 0);
        byte[] info = p.get(P_INFO_BUFFER);
        if (info == null) return response(M_MODIFY, 1);
        if (infoType == 1) {
            int pwdType = p.getInt(P_PWD_TYPE, s.pwdType);
            if (info.length != 32 || pwdType < 1 || pwdType > 5) return response(M_MODIFY, 1);
            s.pwdHash = info;
            s.pwdType = pwdType;
            s.handler = newHandler();
            saveLocked();
            return response(M_MODIFY, 0, P_HANDLER, s.handler);
        } else if (infoType == 2) {
            if (info.length != 32) return response(M_MODIFY, 1);
            s.answerHash = info;
        } else if (infoType == 4) {
            s.email = new String(info);
        } else {
            return response(M_MODIFY, 1);
        }
        saveLocked();
        return response(M_MODIFY, 0);
    }

    private static byte[] delete(Params p) throws Exception {
        Slot s = slot(p, false);
        if (s == null || !challengeValid(s, p.get(P_CHALLENGE))) return response(M_DELETE, 1);
        sSlots.remove(p.getInt(P_PMS_TYPE, 1));
        saveLocked();
        return response(M_DELETE, 0);
    }

    private static String maskEmail(String e) {
        if (e == null || e.isEmpty()) return "";
        int at = e.indexOf('@');
        if (at <= 0) return e.charAt(0) + "***";
        return e.charAt(0) + "***" + e.substring(at);
    }

    private static byte[] getInfo(Params p) throws Exception {
        Slot s = slot(p, false);
        if (s == null || s.pwdHash == null) return response(M_GET_INFO, 0);
        boolean hide = p.getInt(P_HIDE_EMAIL, 1) != 0;
        String email = hide ? maskEmail(s.email) : s.email;
        return response(M_GET_INFO, 0,
                P_PWD_TYPE, s.pwdType,
                P_HANDLER, s.handler,
                P_RETRY_LEFT, RETRY_COUNT,
                P_LOCK_LEFT, 0,
                P_SQ_RETRY_LEFT, RETRY_COUNT,
                P_SQ_LOCK_LEFT, 0,
                P_HIDE_EMAIL, email.isEmpty() ? null : email.getBytes());
    }

    private static void loadLocked() {
        if (sLoaded) return;
        sLoaded = true;
        File f = new File(sStateFile);
        if (!f.exists()) return;
        try (DataInputStream in = new DataInputStream(new FileInputStream(f))) {
            if (in.readInt() != 1) return;
            int n = in.readInt();
            for (int i = 0; i < n; i++) {
                int type = in.readInt();
                Slot s = new Slot();
                s.pwdType = in.readInt();
                s.pwdHash = new byte[in.readInt()];
                in.readFully(s.pwdHash);
                s.handler = new byte[in.readInt()];
                in.readFully(s.handler);
                int al = in.readInt();
                if (al > 0) {
                    s.answerHash = new byte[al];
                    in.readFully(s.answerHash);
                }
                s.email = in.readUTF();
                sSlots.put(type, s);
            }
        } catch (Throwable t) {
            Log.w(TAG, "state load failed: " + t);
            sSlots.clear();
        }
    }

    private static void saveLocked() {
        File f = new File(sStateFile);
        File tmp = new File(sStateFile + ".tmp");
        try {
            try (FileOutputStream fo = new FileOutputStream(tmp);
                 DataOutputStream out = new DataOutputStream(fo)) {
                out.writeInt(1);
                out.writeInt(sSlots.size());
                for (Map.Entry<Integer, Slot> e : sSlots.entrySet()) {
                    Slot s = e.getValue();
                    out.writeInt(e.getKey());
                    out.writeInt(s.pwdType);
                    out.writeInt(s.pwdHash.length);
                    out.write(s.pwdHash);
                    out.writeInt(s.handler.length);
                    out.write(s.handler);
                    out.writeInt(s.answerHash == null ? 0 : s.answerHash.length);
                    if (s.answerHash != null) out.write(s.answerHash);
                    out.writeUTF(s.email == null ? "" : s.email);
                }
                out.flush();
                fo.getFD().sync();
            }
            tmp.setReadable(false, false);
            tmp.setReadable(true, true);
            tmp.setWritable(false, false);
            tmp.setWritable(true, true);
            if (!tmp.renameTo(f)) Log.w(TAG, "state rename failed");
        } catch (Throwable t) {
            Log.w(TAG, "state save failed: " + t);
        }
    }
}
