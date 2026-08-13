# HealthKit mit Sideloadly

Die GitHub-IPA enthält HealthKit bereits (ad-hoc signiert). **Nach dem Sideloadly-Resign fehlt das Entitlement oft**, weil Apple es nur in ein Provisioning-Profil legt, wenn:

1. du ein **bezahltes** Apple Developer Program ($99/Jahr) nutzt, und  
2. für die Bundle-ID `com.noco.running` **HealthKit aktiviert** ist.

Eine **kostenlose** Apple-ID kann HealthKit **nicht** freischalten — dann kommt immer:
`Missing com.apple.developer.healthkit entitlement`.

## Fix (bezahlt)

1. [developer.apple.com](https://developer.apple.com) → Certificates, Identifiers & Profiles → **Identifiers**
2. App-ID **`com.noco.running`** anlegen/öffnen
3. Capability **HealthKit** anhaken → Save
4. Alte Free-App auf dem iPhone **löschen**
5. Sideloadly:
   - Apple ID = **dieselbe bezahlte** Developer-ID
   - Bundle ID **nicht** ändern (oder neue ID ebenfalls mit HealthKit)
   - Advanced Options → Custom Entitlements (falls vorhanden / Patreon) =  
     `SideloadlyHealthKit.entitlements` aus dem Build-Artifact
6. Neu installieren → in NOCO: Mehr → HealthKit → Zugriff anfordern

## Optional: richtig signierte IPA in GitHub Actions

Repo-Secrets setzen:

- `BUILD_CERTIFICATE_BASE64` — .p12 als Base64  
- `P12_PASSWORD`  
- `BUILD_PROVISION_PROFILE_BASE64` — Profil mit HealthKit als Base64  
- `KEYCHAIN_PASSWORD` — beliebiges Passwort für die Runner-Keychain  

Dann Workflow **Build IPA (signed)** ausführen. Ohne diese Secrets bleibt nur die unsigned/Sideloadly-IPA.
