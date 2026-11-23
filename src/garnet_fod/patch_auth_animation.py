#!/usr/bin/env python3
"""Patch a decoded services.jar for an experimental keyguard press animation."""

import argparse
from pathlib import Path

CLASS = "Lcom/android/server/biometrics/sensors/fingerprint/aidl/FingerprintAuthenticationClient;"
RELATIVE = Path("smali/com/android/server/biometrics/sensors/fingerprint/aidl/FingerprintAuthenticationClient.smali")
METHODS = Path(__file__).with_name("auth_animation_methods.smali")

HOOKS = {
    ".method public onAcquired(II)V":
        f"invoke-direct {{p0, p1, p2}}, {CLASS}->garnetAnimationAcquired(II)V",
    ".method public onAuthenticated(Landroid/hardware/biometrics/BiometricAuthenticator$Identifier;ZLjava/util/ArrayList;)V":
        f"invoke-direct {{p0, p2}}, {CLASS}->garnetAnimationFinish(Z)V",
    ".method public onError(II)V": f"invoke-direct {{p0}}, {CLASS}->garnetAnimationClose()V",
    ".method public onLockoutPermanent()V": f"invoke-direct {{p0}}, {CLASS}->garnetAnimationClose()V",
    ".method public onLockoutTimed(J)V": f"invoke-direct {{p0}}, {CLASS}->garnetAnimationClose()V",
    ".method protected stopHalOperation()V": f"invoke-direct {{p0}}, {CLASS}->garnetAnimationClose()V",
}


def patch(text, additions):
    if "garnetAnimationAcquired" in text or "mGarnetAnimationPressed" in text:
        raise ValueError("Fingerprint animation patch already present")
    field_marker = "# instance fields\n"
    if text.count(field_marker) != 1:
        raise ValueError("Expected one instance fields marker")
    fields, methods = additions.split("\n\n", 1)
    text = text.replace(field_marker, field_marker + fields + "\n\n", 1)
    for signature, hook in HOOKS.items():
        if text.count(signature + "\n") != 1:
            raise ValueError(f"Expected one method: {signature}")
        start = text.index(signature + "\n")
        end = text.index("\n.end method", start)
        line = text.find("\n    .line ", start, end)
        if line < 0:
            raise ValueError(f"Missing first line: {signature}")
        text = text[:line] + "\n    " + hook + "\n" + text[line:]
    return text + "\n" + methods


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("decoded", type=Path)
    args = parser.parse_args()
    path = args.decoded / RELATIVE
    original = path.read_text(encoding="utf-8")
    result = patch(original, METHODS.read_text(encoding="utf-8"))
    path.write_text(result, encoding="utf-8")


if __name__ == "__main__":
    main()
