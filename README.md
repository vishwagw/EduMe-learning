# Edume Learning — Production Deploy Guide

## Complete File Structure

```
edume-learning/
├── index.html                     Landing page
├── login.html                     Login (email + Google)
├── signup.html                    Signup with role selection
├── courses.html                   ★ Course catalog browse + search + filters
├── course.html                    ★ Course detail page + buy button
├── course-player.html             ★ Video player + progress tracking
├── course-builder.html            ★ Instructor course builder + video upload
├── checkout.html                  ★ PayHere payment checkout
├── payment-success.html           ★ Post-payment confirmation
├── student-dashboard.html         Student dashboard
├── instructor-dashboard.html      Instructor dashboard (earnings + stats)
├── live-classes.html              Live class browse + buy tickets
├── css/styles.css                 Shared design system
├── js/
│   ├── supabase-client.js         Supabase client + helpers
│   └── ui.js                      Toast + nav + formatters
├── supabase/functions/
│   ├── payhere-hash/index.ts      ★ Edge Function: PayHere hash (server-side)
│   └── payhere-notify/index.ts    ★ Edge Function: Payment webhook handler
├── supabase-schema.sql            Base DB schema (run first)
├── schema-additions.sql           ★ Production schema additions (run second)
└── vercel.json                    Vercel routing + security headers
```

---

## Step 1 — Supabase Setup

### 1.1 Run Schema
In Supabase → SQL Editor, run these **in order**:
1. `supabase-schema.sql`
2. `schema-additions.sql`

### 1.2 Install Supabase CLI
```bash
npm install -g supabase
supabase login
supabase link --project-ref YOUR_PROJECT_ID
```
Your project ID is in: Supabase Dashboard → Settings → General

### 1.3 Deploy Edge Functions
```bash
supabase functions deploy payhere-hash
supabase functions deploy payhere-notify
```

### 1.4 Set Edge Function Secrets
```bash
supabase secrets set PAYHERE_MERCHANT_ID=your_merchant_id
supabase secrets set PAYHERE_MERCHANT_SECRET=your_merchant_secret
```

Get your PayHere credentials at: https://www.payhere.lk/merchant/settings

---

## Step 2 — PayHere Setup

1. Sign up at https://www.payhere.lk/merchant/register
2. Go to Settings → Domains and add your Vercel domain
3. Copy your Merchant ID and Merchant Secret
4. Set them as Supabase secrets (Step 1.4 above)

### Switch from Sandbox to Live
In `checkout.html`, change the form action:
```html
<!-- Sandbox (testing) -->
<form action="https://sandbox.payhere.lk/pay/checkout">

<!-- Production (live payments) -->
<form action="https://www.payhere.lk/pay/checkout">
```

---

## Step 3 — Configure Supabase Keys

Open `js/supabase-client.js` and replace:
```javascript
const SUPABASE_URL     = 'https://YOUR_PROJECT_ID.supabase.co';
const SUPABASE_ANON_KEY= 'YOUR_ANON_KEY';
```

Get these from: Supabase → Settings → API

---

## Step 4 — Deploy to Vercel

```bash
git init
git add .
git commit -m "Production Edume Learning platform"
git remote add origin https://github.com/YOUR_USERNAME/edume-learning.git
git push -u origin main
```

Then: Vercel → Import Repo → Framework: Other → Deploy

### After deployment:
1. Update Supabase Site URL: `https://your-site.vercel.app`
2. Add redirect URL: `https://your-site.vercel.app/**`
3. Update PayHere domain allowlist with your Vercel URL

---

## Step 5 — First Instructor Account

1. Sign up on the site as **Teacher**
2. In Supabase → Table Editor → `profiles`, confirm `role = 'instructor'`
3. Log in → you'll land on the Instructor Dashboard
4. Click **"+ Create Course"** → opens Course Builder
5. Add sections, upload videos, publish

---

## Key User Flows

### Student Buys a Course
1. Browse `/courses.html` → click course → `/course.html?id=XXX`
2. Click "Enroll Now" → `/checkout.html?type=course&id=XXX`
3. Fill contact info → click "Pay via PayHere"
4. Complete payment on PayHere → redirected to `/payment-success.html`
5. PayHere calls `/functions/v1/payhere-notify` webhook → enrollment created in DB
6. Student can now access `/course-player.html?id=XXX`

### Instructor Publishes a Course
1. Instructor Dashboard → "+ Create Course"
2. Fills basic info → course is created as Draft
3. Clicks "Edit" → opens `/course-builder.html?id=XXX`
4. Adds sections → adds lessons → uploads videos (with progress bar)
5. Uploads PDF resources
6. Clicks "Publish Course" → course goes live on `/courses.html`

### Student Watches Videos
1. Opens course player → video loads via Supabase signed URL (secure, time-limited)
2. Progress saves every 15 seconds + on video end
3. Sidebar shows completion checkmarks
4. 90% watched = auto-marked complete
5. All lessons done = certificate unlocked

---

## Production Checklist

- [ ] Supabase project in Singapore region
- [ ] Both SQL files executed in order
- [ ] Edge functions deployed: `payhere-hash`, `payhere-notify`
- [ ] PayHere credentials set as Supabase secrets
- [ ] `SUPABASE_URL` and `SUPABASE_ANON_KEY` in `supabase-client.js`
- [ ] Vercel deployed + custom domain configured
- [ ] PayHere domain allowlist updated
- [ ] PayHere form action switched from sandbox to live
- [ ] Google OAuth configured (optional but recommended)
- [ ] Supabase Auth redirect URLs updated with production domain
- [ ] Storage buckets created: course-thumbnails, course-videos, course-resources, avatars

---

## What's Next

| Feature | Tool |
|---------|------|
| Adaptive video streaming | Bunny.net (replace Supabase Storage for videos) |
| Transactional emails | Resend + Supabase Edge Functions |
| Student certificates (PDF) | Puppeteer or a PDF generation API |
| Analytics | Supabase's built-in analytics or Plausible |
| Mobile app | Capacitor.js (wraps this HTML/JS into iOS + Android) |
| Admin panel | Add `/admin.html` with service role key checks |
