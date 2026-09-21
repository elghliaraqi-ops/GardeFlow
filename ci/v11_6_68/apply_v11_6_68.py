from pathlib import Path

def show(path, needles, radius=18):
    p=Path(path)
    if not p.exists():
        print(f"DIAG missing {path}")
        return
    lines=p.read_text(errors="replace").splitlines()
    for needle in needles:
        found=False
        for i,line in enumerate(lines):
            if needle in line:
                found=True
                a=max(0,i-radius); b=min(len(lines),i+radius+1)
                print(f"\n===== {path} :: {needle} @ {i+1} =====")
                for j in range(a,b):
                    print(f"{j+1}: {lines[j]}")
        if not found:
            print(f"DIAG {path}: needle not found: {needle}")

show("lib/state/app_state.dart",[
    "Future<void> logout",
    "Future<bool> login",
    "Future<void> login",
    "_dismissedNotificationKeys",
    "forceSyncMyOfficialRoster",
],28)
show("lib/services/push_notification_service.dart",[
    "class PushNotificationService",
    "activateForSignedInUser",
    "unregisterCurrentDevice",
    "onTokenRefresh",
],35)
show("lib/services/notification_service.dart",[
    "Future<void> cancelAll",
    "cancelGuardReminders",
],25)
show("lib/screens/official_planning_screen.dart",[
    "_myCanResync",
    "Refaire la superposition",
],24)
print("V11.6.68 diagnostics complete")
