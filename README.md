# Reindeer Games

Emerald Bay's neighborhood Rudolph-stealing game. Families steal an inflatable Rudolph from each other all December and log each capture here with photos and videos.

- **Site:** hosted on GitHub Pages from this repo (`index.html`).
- **Data:** families, steals, sign-ins, photos and videos live in a Firebase project. Nothing about the game is stored in this repo.

## Files

| File | What it is |
| --- | --- |
| `index.html` | The whole site |
| `config.js` | Your Firebase web app settings (public by design) |
| `assets/` | Emerald Bay map images (light and dark) |
| `firebase/firestore.rules` | Who can read and change game data |
| `firebase/storage.rules` | Who can view and upload photos and videos |

## One-time setup

### 1. Create the Firebase project
1. At [console.firebase.google.com](https://console.firebase.google.com), click **Create a project**. Google Analytics isn't needed.
2. Upgrade to the **Blaze** plan (bottom left, **Upgrade**). Firebase requires it for photo and video storage. A neighborhood game stays within the no-cost amounts. Set a budget alert (for example $1) when asked.

### 2. Register the website
1. Go to **Project settings → General → Your apps**, click the **</>** (Web) icon, and register an app named `Reindeer Games`. Don't enable Firebase Hosting.
2. Copy the `firebaseConfig` values into `config.js`.

### 3. Turn on sign-in
1. Go to **Build → Authentication → Get started → Sign-in method**.
2. Enable **Google**, and **Email/Password** with **Email link (passwordless sign-in)** switched on.
3. Under **Authentication → Settings → Authorized domains**, add `westwoodeleven.github.io`.

### 4. Create the database
1. Go to **Build → Firestore Database → Create database**. Pick a US location (for example `us-west1`) and **production mode**.
2. Open the **Rules** tab, replace everything with `firebase/firestore.rules`, and click **Publish**.
3. Make yourself the organizer. On the **Data** tab, **Start collection** `organizers`. Set the document ID to your sign-in email in lower case, and add any field (for example `role` = `organizer`).

### 5. Create photo storage
1. Go to **Build → Storage → Get started**. Use the same US location (US-WEST1, US-CENTRAL1 or US-EAST1 are in the no-cost tier).
2. Open the **Rules** tab, replace everything with `firebase/storage.rules`, and click **Publish**.

### 6. Turn on GitHub Pages
In this repo: **Settings → Pages → Deploy from a branch → `main` / root**.

## How access works
- Anyone can open the site, but they only see a sign-in screen.
- After signing in with Google or an emailed link, a family requests to join. The organizer approves them under **Organizer → Join requests**, which creates their home and a `members` entry.
- Only approved families and organizers can read anything. Only organizers can add, edit or remove families.
- The newest steal is hidden on screen from everyone except the organizer and the two families involved, until Rudolph is stolen again.

## Limits
- Photos and videos: up to 100 MB per file.
- Storage no-cost tier (US regions): about 5 GB stored and plenty of downloads for a neighborhood. Check **Usage and billing** in Firebase now and then.
