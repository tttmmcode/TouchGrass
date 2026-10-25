# TouchGrass — App Store & Play Store Listing

---

## APP STORE (iOS / App Store Connect)

### Name
TouchGrass

### Subtitle (30 chars max)
Daily outdoor challenges & XP

### Promotional Text (170 chars max — updates without re-review)
New challenges every day. Snap a photo, earn XP, climb the league. Your streak is waiting — step outside and TouchGrass.

### Description (4000 chars max)

**Stop scrolling. Start exploring.**

TouchGrass gives you a fresh outdoor challenge every single day — from spotting wildlife to discovering a hidden street, practicing mindfulness in a park to photographing something beautiful near you.

Complete your challenge, snap a photo, and add it to your Journal. Earn XP, build streaks, and climb through 8 leagues alongside thousands of other explorers.

**WHY TOUCHGRASS?**

Research shows that spending just 20 minutes outside in nature meaningfully reduces stress, improves mood, and boosts creativity. TouchGrass turns that science into a daily habit — one small adventure at a time.

**FEATURES**

• Daily Challenge Path — A beautifully designed trail of today's challenge and your recent history
• Photo Journal — Every completed challenge is saved with your photo in your own Journal
• 8 Adventure Leagues — Seedling → Sprout → Explorer → Pathfinder → Trailblazer → Wanderer → Voyager → Aurora
• XP & Leveling — Earn points for every completion and watch your level climb
• Streaks & Rainy Days — Build daily streaks; Rainy Days protect your streak on busy days
• Adventure Map — See every place you've been, filtered by challenge category
• 50+ Achievements — Unlock badges for milestones, streaks, and special moments
• Companion Characters — A woodland friend celebrates every completion with you
• Weekly Leaderboard — Compete in your league for the top 5 promotion spots
• Beautiful Design — Premium dark & light themes that feel as good as the outdoors

**HOW IT WORKS**

1. Open TouchGrass — your daily challenge is waiting
2. Step outside and complete it (5–40 minutes depending on difficulty)
3. Snap a photo proof
4. Save it to your Journal
5. Earn XP, advance your streak, unlock achievements

**PERFECT FOR**
• People who spend too much time on screens
• Anyone wanting a gentle exercise habit
• Nature lovers and urban explorers
• Mindfulness and wellness seekers
• Competitive players who love leaderboards

Start with a free account. No subscriptions, no ads, no nonsense.

**Privacy:** TouchGrass only stores what you share, and never sells your data. With "Save location with adventures" on, your Journal entries are tagged with where they happened, and your approximate location is used to show local weather. Turn it off any time in Settings → Privacy.

### Keywords (100 chars max — comma-separated, no spaces after commas)
outdoor,nature,challenge,adventure,streak,fitness,wellness,explore,mindfulness,steps,XP,habit

### Categories
Primary: Health & Fitness
Secondary: Lifestyle

### Age Rating
4+ (no objectionable content)

### Privacy Policy URL
https://touchgrass.app/privacy  (⚠️ HOST THIS PAGE BEFORE SUBMISSION)

### Support URL
https://touchgrass.app/support  (⚠️ HOST THIS PAGE BEFORE SUBMISSION)

### Copyright
© 2025 TouchGrass. All rights reserved.

---

## PLAY STORE (Android / Google Play Console)

### Title (50 chars max)
TouchGrass: Daily Outdoor Challenges

### Short Description (80 chars max)
Complete daily outdoor challenges, earn XP & climb adventure leagues.

### Full Description (4000 chars max)
[Use the same App Store description above]

### App Category
Health & Fitness

### Tags
outdoor activity, nature, wellness, habit tracker, adventure, exploration

### Content Rating
Everyone

### Privacy Policy URL
https://touchgrass.app/privacy  (⚠️ HOST THIS PAGE BEFORE SUBMISSION)

---

## DATA SAFETY FORM (Google Play)

### Data collected and shared

| Data Type | Collected | Shared | Required | Purpose |
|-----------|-----------|--------|----------|---------|
| Name | Yes | No | No (display only) | Show username in profile/leaderboard |
| Email address | Yes | No | Yes | Account creation & authentication |
| User IDs | Yes | No | Yes | Link data to user account |
| Photos & videos | Yes | No | No | Challenge photos shown in the user's Journal; optional profile photo shown on the leaderboard |
| Location (see note) | Yes, optional | **Owner to confirm** (see note) | No ("Save location with adventures" setting) | Tag Journal entries on the map; local weather |
| Crash logs | Yes | No | Yes (Firebase Crashlytics) | App stability |
| App interactions | Yes | No | No (Firebase Analytics) | Improve app experience |
| App performance | Yes | No | No (Firebase Performance) | Optimize load times |

> **Location note (2026-10-17, remediation D-09) — decide before submitting the form:**
> - **Precise or approximate?** The app requests fine location and stores the coordinates it receives (medium accuracy, roughly 100 m) with completions and Journal entries, so Play will likely classify this as **precise** location.
> - **Shared?** While the setting is on, coordinates rounded to ~1 km are sent to **Open-Meteo** for weather, and coordinates are sent to the platform geocoder (Apple/Google) for place names. Whether that counts as "sharing" under Play's definitions (which exempt service providers acting on your behalf) is the owner's call.
> - **Off:** with the setting off, none of this is collected or sent.
> - Full flow table: `REMEDIATION_CHECKLIST.md` → Phase 3 → "Location data flows".

### Data handling
- All data is encrypted in transit (HTTPS / TLS 1.3)
- Firebase services store data on Google Cloud (US regions by default)
- Users can request account deletion from Settings → Delete Account. **Release gate (Phase 7D):** this works only once the `deleteAccount` Cloud Function is deployed and tested live (`PHASE_7D_ACCOUNT_DELETION_REMEDIATION.md`); don't declare in-app deletion before that.
- Completion photos are stored in Firebase Storage under the user's UID. Other users can't browse or open them in the app; each photo is delivered through a private link that works for anyone it is shared with.
- Profile photos are shown to other signed-in users on the leaderboard.
- No AI service receives photos (AI verification is disabled).

### Does your app share user data with third parties?
Yes — Firebase (Google) for authentication, database, analytics, crash reporting, and push notifications. See Privacy Policy for details.

---

## APP STORE SCREENSHOTS GUIDE

### iPhone (6.9" — iPhone 16 Pro Max)
Required: 3–10 screenshots at 1320 × 2868 px

Suggested sequence:
1. Home screen — Adventure trail with today's challenge glowing
2. Challenge detail — Beautiful challenge card with category and difficulty
3. Camera — Taking a photo of the challenge
4. Success screen — Confetti + XP reward + companion celebration
5. Map screen — Adventure memories scattered across the map
6. Leaderboard — League standings with promotion/demotion zones
7. Profile — Achievements, streak, level progress
8. Dark mode — Home screen showing premium dark theme

### Android (Phone — 9:16 ratio, min 1080px wide)
Same 8 screenshots at 1080 × 1920 px minimum

### Feature Graphic (Android only, required)
Size: 1024 × 500 px
Content: App name + tagline "Stop scrolling. Start exploring." on forest green background

---

## RELEASE NOTES (What's New — Version 1.0.0)

First release! 🌿

• A new outdoor challenge every day
• A photo Journal of your adventures
• 8 adventure leagues with weekly leaderboards
• 50+ achievements to unlock
• Beautiful adventure memory map
• Streak tracking with Rainy Day protection
• Dark and light themes
