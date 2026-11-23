.field private mGarnetAnimationPressed:Z
.field private mGarnetAnimationClosed:Z

.method private garnetAnimationAcquired(II)V
    .locals 3

    iget-boolean v0, p0, Lcom/android/server/biometrics/sensors/fingerprint/aidl/FingerprintAuthenticationClient;->mGarnetAnimationClosed:Z
    if-nez v0, :done

    const/4 v0, 0x6
    if-ne p1, v0, :done

    invoke-virtual {p0}, Lcom/android/server/biometrics/sensors/fingerprint/aidl/FingerprintAuthenticationClient;->getRequestReason()I
    move-result v0
    const/4 v1, 0x4
    if-ne v0, v1, :done

    const/16 v0, 0x16
    if-ne p2, v0, :check_up

    invoke-virtual {p0}, Lcom/android/server/biometrics/sensors/fingerprint/aidl/FingerprintAuthenticationClient;->getContext()Landroid/content/Context;
    move-result-object v0
    const-class v1, Landroid/os/PowerManager;
    invoke-virtual {v0, v1}, Landroid/content/Context;->getSystemService(Ljava/lang/Class;)Ljava/lang/Object;
    move-result-object v0
    check-cast v0, Landroid/os/PowerManager;
    if-eqz v0, :done
    invoke-virtual {v0}, Landroid/os/PowerManager;->isInteractive()Z
    move-result v0
    if-eqz v0, :done

    invoke-virtual {p0}, Lcom/android/server/biometrics/sensors/fingerprint/aidl/FingerprintAuthenticationClient;->getContext()Landroid/content/Context;
    move-result-object v0
    const-class v1, Landroid/hardware/display/DisplayManager;
    invoke-virtual {v0, v1}, Landroid/content/Context;->getSystemService(Ljava/lang/Class;)Ljava/lang/Object;
    move-result-object v0
    check-cast v0, Landroid/hardware/display/DisplayManager;
    if-eqz v0, :done
    const/4 v1, 0x0
    invoke-virtual {v0, v1}, Landroid/hardware/display/DisplayManager;->getDisplay(I)Landroid/view/Display;
    move-result-object v0
    if-eqz v0, :done
    invoke-virtual {v0}, Landroid/view/Display;->getState()I
    move-result v0
    const/4 v1, 0x2
    if-ne v0, v1, :done

    const/4 v0, 0x1
    invoke-direct {p0, v0}, Lcom/android/server/biometrics/sensors/fingerprint/aidl/FingerprintAuthenticationClient;->garnetAnimationSet(Z)V
    return-void

    :check_up
    const/16 v0, 0x17
    if-ne p2, v0, :done
    const/4 v0, 0x0
    invoke-direct {p0, v0}, Lcom/android/server/biometrics/sensors/fingerprint/aidl/FingerprintAuthenticationClient;->garnetAnimationSet(Z)V
    :done
    return-void
.end method

.method private garnetAnimationSet(Z)V
    .locals 3

    iget-boolean v0, p0, Lcom/android/server/biometrics/sensors/fingerprint/aidl/FingerprintAuthenticationClient;->mGarnetAnimationPressed:Z
    if-eq v0, p1, :done
    iput-boolean p1, p0, Lcom/android/server/biometrics/sensors/fingerprint/aidl/FingerprintAuthenticationClient;->mGarnetAnimationPressed:Z
    if-eqz p1, :up
    const/16 v1, 0x8
    goto :send
    :up
    const/16 v1, 0x9
    :send
    iget-object v0, p0, Lcom/android/server/biometrics/sensors/fingerprint/aidl/FingerprintAuthenticationClient;->mSensorOverlays:Lcom/android/server/biometrics/sensors/SensorOverlays;
    invoke-virtual {p0}, Lcom/android/server/biometrics/sensors/fingerprint/aidl/FingerprintAuthenticationClient;->getSensorId()I
    move-result v2
    invoke-virtual {v0, v2, v1, p0}, Lcom/android/server/biometrics/sensors/SensorOverlays;->show(IILcom/android/server/biometrics/sensors/AcquisitionClient;)V
    :done
    return-void
.end method

.method private garnetAnimationFinish(Z)V
    .locals 1

    const/4 v0, 0x0
    invoke-direct {p0, v0}, Lcom/android/server/biometrics/sensors/fingerprint/aidl/FingerprintAuthenticationClient;->garnetAnimationSet(Z)V
    if-eqz p1, :done
    const/4 v0, 0x1
    iput-boolean v0, p0, Lcom/android/server/biometrics/sensors/fingerprint/aidl/FingerprintAuthenticationClient;->mGarnetAnimationClosed:Z
    :done
    return-void
.end method

.method private garnetAnimationClose()V
    .locals 1

    const/4 v0, 0x1
    invoke-direct {p0, v0}, Lcom/android/server/biometrics/sensors/fingerprint/aidl/FingerprintAuthenticationClient;->garnetAnimationFinish(Z)V
    return-void
.end method
