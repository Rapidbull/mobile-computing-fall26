# Split Tracker — Milestone 4 Firebase Setup

This is the existing Split Tracker semester project, not the Cloud Notes scratch project.

## Firebase Console (manual steps)
1. Create a NEW Firebase project named split-tracker at https://console.firebase.google.com.
2. Authentication > Sign-in method: enable Email/Password.
3. Firestore Database > Create: Standard edition, US location (e.g. nam5), production mode.
4. Firestore > Rules: paste the contents of firestore.rules from this folder and click Publish.

## Connect Flutter (Windows PowerShell)
From the repository root, run:

    cd myApp_Split_Tracker/split_tracker
    flutter pub get
    npm install -g firebase-tools
    firebase login
    dart pub global activate flutterfire_cli
    flutterfire configure --platforms=android,web

Select the NEW split-tracker Firebase project. The last command generates lib/firebase_options.dart.
If the flutterfire command is not found, add %LOCALAPPDATA%\Pub\Cache\bin to PATH, reopen PowerShell, and retry.
Do NOT create firebase_options.dart manually and do not reuse credentials from the Cloud Notes lab.
Commit the generated firebase_options.dart, platform configuration, and refreshed pubspec.lock after confirming there are no private service-account credentials.
Until you run flutterfire configure, main.dart cannot compile because the project-specific generated file is missing.

## Authentication
LoginScreen supports email-password sign-up and sign-in with friendly errors. AuthGate uses FirebaseAuth.instance.authStateChanges() with StreamBuilder to display either LoginScreen or HomeScreen. The home app bar has a logout button. RaceAppModel is created separately for each logged-in account.

## Data storage
- Split goals: users/{uid}/goals/{auto-id}, fields distance, goalSeconds, createdAt, updatedAt. Results screen writes records; the home page uses StreamBuilder to render live saved goals, with edit and delete buttons.
- Next race: users/{uid}/saved/nextRace, fields id, name, date, city, state, street, website. Save/remove actions use Firestore, and a document snapshot listener updates the UI.
- Race search from RunSignup and weather from Open-Meteo remain live public API requests, unchanged.
- Temporary calculator inputs are not saved unless the user presses Save Goal to Cloud.
- Previously saved SharedPreferences next-race values are not automatically migrated. Save the selected race again after login.

## Access rules
firestore.rules only allows a request if request.auth is non-null and request.auth.uid equals the owner userId. The recursive rule covers all user subcollections and denies other paths by default. Publish these rules in the Firebase console.

## Testing and submission
1. Run flutter analyze and flutter run -d chrome or Android emulator.
2. Sign up, log out, demonstrate failed login error, then log in.
3. Calculate and save a goal, edit it, and check Firestore Data > users > your uid > goals.
4. Find and save a next race, check Firestore Data > users > your uid > saved > nextRace.
5. Log out and back in and show that goals and next race persist; optionally verify a second account sees separate data.
6. Record a demo showing these steps and the Firebase Console; submit the SAME GitHub repository URL and your demo animation.

Run flutter pub get to regenerate pubspec.lock; do not leave the old lockfile out of sync.
This is Firebase, so the optional CLOUD_SETUP.md file required for alternative services is not needed.
