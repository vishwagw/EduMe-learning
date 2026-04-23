// ============================================================
//  Edume Learning — Supabase Client
//  Replace SUPABASE_URL and SUPABASE_ANON_KEY with your values
//  from: https://supabase.com/dashboard → Project Settings → API
// ============================================================

const SUPABASE_URL = window.__ENV__?.SUPABASE_URL || 'https://YOUR_PROJECT_ID.supabase.co';
const SUPABASE_ANON_KEY = window.__ENV__?.SUPABASE_ANON_KEY || 'YOUR_ANON_KEY';

const { createClient } = supabase;
const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// ---- Realtime channel for live-class notifications ----
const notifChannel = sb.channel('live-notifications');

async function subscribeToNotifications(userId, onMessage) {
  notifChannel
    .on('postgres_changes', {
      event: 'INSERT',
      schema: 'public',
      table: 'notifications',
      filter: `user_id=eq.${userId}`
    }, payload => onMessage(payload.new))
    .subscribe();
}

// ---- Auth helpers ----
async function getCurrentUser() {
  const { data: { user } } = await sb.auth.getUser();
  return user;
}

async function getCurrentProfile() {
  const user = await getCurrentUser();
  if (!user) return null;
  const { data } = await sb.from('profiles').select('*').eq('id', user.id).single();
  return data;
}

// ---- Redirect helpers ----
function requireAuth(redirectTo = '/login.html') {
  getCurrentUser().then(user => {
    if (!user) window.location.href = redirectTo;
  });
}

function redirectIfLoggedIn(redirectTo = '/student-dashboard.html') {
  getCurrentUser().then(user => {
    if (user) window.location.href = redirectTo;
  });
}

// ---- Storage helpers ----
async function uploadFile(bucket, path, file) {
  const { data, error } = await sb.storage.from(bucket).upload(path, file, {
    cacheControl: '3600',
    upsert: true
  });
  if (error) throw error;
  return sb.storage.from(bucket).getPublicUrl(path).data.publicUrl;
}

// ---- Expose ----
window.edumeDB = {
  sb,
  getCurrentUser,
  getCurrentProfile,
  requireAuth,
  redirectIfLoggedIn,
  subscribeToNotifications,
  uploadFile,
};
