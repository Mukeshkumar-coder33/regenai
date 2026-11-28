# ReGen Production FCM & Persistent Backend Deployment Guide

This guide preserves Firebase Admin SDK credentials **outside Git** so `git pull` deployments never overwrite, expose, or erase your credentials.

---

## 1. Security Rules (Critical)
- **Never commit** `.env` or `firebase-service-account.json` to Git.
- **Never place** `firebase-service-account.json` inside `mobile_app/` or `frontend/`.
  - `mobile_app/android/app/google-services.json` is the **Android client config** (`com.mukeshkumar_coder33.regen_mobile`).
  - `firebase-service-account.json` is the **Node.js backend Admin private key**.
- **If any Firebase private key was ever committed or shared publicly:** immediately revoke that key in Firebase Console -> Project Settings -> Service Accounts -> Manage service account permissions -> Delete key, and generate a new private key JSON.

---

## 2. Backend Credential Loading Priority
[fcmPush.js](../server/utils/fcmPush.js) automatically validates and loads credentials at startup (`initializeFcmStartup()` in `server/index.js`) in this deterministic priority order:

1. `FIREBASE_SERVICE_ACCOUNT_PATH` (recommended for production: `/etc/regen/secrets/firebase-service-account.json`)
2. `FIREBASE_SERVICE_ACCOUNT_JSON` (raw JSON or base64-encoded JSON)
3. `GOOGLE_APPLICATION_CREDENTIALS`
4. `reGen/server/firebase-service-account.json` (untracked local dev path)
5. `/etc/regen/secrets/firebase-service-account.json` (persistent Linux production fallback)

---

## 3. One-Time Production Server Setup (Linux)

Run once on the production server (replace `<SERVICE_USER>` with the Linux account running Node/PM2, e.g., `whoami`):

```bash
# 1. Create persistent secret directory outside the Git repository
sudo mkdir -p /etc/regen/secrets
sudo chown <SERVICE_USER>:<SERVICE_USER> /etc/regen/secrets
sudo chmod 700 /etc/regen/secrets

# 2. Upload or create /etc/regen/secrets/firebase-service-account.json securely (chmod 600)
# Example using scp from your local machine:
# scp ./firebase-service-account.json <USER>@<SERVER>:/etc/regen/secrets/firebase-service-account.json
sudo chmod 600 /etc/regen/secrets/firebase-service-account.json
sudo chown <SERVICE_USER>:<SERVICE_USER> /etc/regen/secrets/firebase-service-account.json

# 3. Configure persistent server .env (also untracked by Git)
# Add inside <SERVER_REPO_DIR>/reGen/server/.env:
#   FIREBASE_SERVICE_ACCOUNT_PATH=/etc/regen/secrets/firebase-service-account.json
#   NODE_ENV=production
#   PORT=5006
```

### Persistent Process Manager (PM2 — matches `/api/system/pm2-status`)

```bash
cd <SERVER_REPO_DIR>/reGen/server
npm install --omit=dev
pm2 start index.js --name regen-backend --cwd <SERVER_REPO_DIR>/reGen/server
pm2 save
pm2 startup
# Run the sudo env PATH=... command output by `pm2 startup` so backend auto-starts on reboot
```

*(Alternative `systemd` unit if not using PM2 — use one process manager only, do not run both simultaneously)*:

```ini
# /etc/systemd/system/regen-backend.service
[Unit]
Description=ReGen Workforce Management Backend
After=network.target mongod.service

[Service]
Type=simple
User=<SERVICE_USER>
WorkingDirectory=<SERVER_REPO_DIR>/reGen/server
Environment=NODE_ENV=production
Environment=FIREBASE_SERVICE_ACCOUNT_PATH=/etc/regen/secrets/firebase-service-account.json
ExecStart=/usr/bin/node index.js
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

---

## 4. Future Deployments (Zero Credential Reconfiguration)

After the one-time setup above, future code deployments follow:

```bash
cd <SERVER_REPO_DIR>/reGen
git pull origin mukesh-app
cd server
npm install --omit=dev
pm2 restart regen-backend   # (or: sudo systemctl restart regen-backend)
```

Verify startup logs and health immediately:
```bash
pm2 logs regen-backend --lines 30
# Look for:
#   Server running on http://0.0.0.0:5006 (with WebSocket)
#   [FCM] Ready (project=regen-929cc, source=FIREBASE_SERVICE_ACCOUNT_PATH (/etc/regen/secrets/firebase-service-account.json))
curl -fsS http://127.0.0.1:5006/api/health
```

---

## 5. Two-Device Physical Android Test Checklist

Prerequisites before testing push delivery on phones:
- Place `google-services.json` (Android client config for `com.mukeshkumar_coder33.regen_mobile`, project `regen-929cc`) in `reGen/mobile_app/android/app/google-services.json` and rebuild `app-release.apk`.
- Place your Firebase Admin service account JSON at `reGen/server/firebase-service-account.json` (local) or `/etc/regen/secrets/firebase-service-account.json` (production) and restart the backend.

1. User A and User B signed in on two Android devices.
2. Direct text message (Messenger open, other module open, background, swiped away).
3. Group chat message delivery + notification sound respect.
4. Voice note message + tray notification.
5. Media image/video message.
6. Document attachment message.
7. Incoming audio call (foreground, other module, background, locked screen, swiped away).
8. Incoming video call (same states).
9. Incoming group meeting invite & join.
10. Reject call (ringtone stops on caller & all receiver devices).
11. Accept call (ringtone stops everywhere, call connects).
12. Caller cancels before answer (ringtone & call tray notification cancel immediately, missed call appears).
13. Ring timeout (45s server / 48s client) stops ringtone & logs missed call.
14. Foreground in-app banner + sound without duplicate Android tray notification.
15. Background & swiped-away Android tray notification + correct module launch on tap.
16. Account switch / logout: device token unlinked from old account and bound only to new user.
17. Reconnect message & notification recovery after toggling Airplane mode / Wi-Fi ↔ Mobile Data.
18. Verification against both local (`http://192.168.1.38:5006`) and production (`https://regen.krishub.in`) without cross-environment token leak.
