// ============================================================
//  Edume Learning — UI Utilities (toast, nav, modals)
// ============================================================

// ---- Toast ----
function showToast(message, type = 'info', duration = 4000) {
  let container = document.getElementById('toast-container');
  if (!container) {
    container = document.createElement('div');
    container.id = 'toast-container';
    document.body.appendChild(container);
  }
  const icons = { success: '✅', error: '❌', info: 'ℹ️' };
  const toast = document.createElement('div');
  toast.className = `toast ${type}`;
  toast.innerHTML = `<span>${icons[type]}</span><span>${message}</span>`;
  container.appendChild(toast);
  setTimeout(() => toast.remove(), duration);
}

// ---- Render shared nav ----
function renderNav(activePage = '') {
  const nav = document.getElementById('app-nav');
  if (!nav) return;
  edumeDB.getCurrentProfile().then(profile => {
    const initials = profile
      ? (profile.full_name || 'U').split(' ').map(n => n[0]).join('').toUpperCase().slice(0, 2)
      : '?';
    const dashLink = profile?.role === 'instructor'
      ? '/instructor-dashboard.html'
      : '/student-dashboard.html';

    nav.innerHTML = `
      <a href="/index.html" class="app-nav-logo">
        <div class="app-nav-logo-icon">E</div>
        Edume
      </a>
      <div style="display:flex;align-items:center;gap:1.5rem">
        <a href="/index.html#courses" style="font-size:0.875rem;color:var(--ink-muted);text-decoration:none;font-weight:500">Courses</a>
        <a href="/live-classes.html" style="font-size:0.875rem;color:var(--ink-muted);text-decoration:none;font-weight:500">Live Classes</a>
        ${profile ? '' : '<a href="/index.html#teach" style="font-size:0.875rem;color:var(--ink-muted);text-decoration:none;font-weight:500">Teach</a>'}
      </div>
      <div class="app-nav-right">
        ${profile ? `
          <div class="notif-bell" onclick="toggleNotifPanel()" title="Notifications">
            🔔
            <span class="notif-count" id="notif-count" style="display:none">0</span>
          </div>
          <a href="${dashLink}" class="avatar" title="${profile.full_name}">${initials}</a>
          <button class="btn btn-secondary" onclick="signOut()">Sign out</button>
        ` : `
          <a href="/login.html" class="btn btn-secondary">Log in</a>
          <a href="/signup.html" class="btn btn-primary">Get Started</a>
        `}
      </div>
    `;

    if (profile) {
      // Subscribe to realtime notifications
      edumeDB.subscribeToNotifications(profile.id, (notif) => {
        showToast(notif.message, 'info');
        incrementNotifBadge();
      });
    }
  });
}

function incrementNotifBadge() {
  const badge = document.getElementById('notif-count');
  if (!badge) return;
  const current = parseInt(badge.textContent || '0');
  badge.textContent = current + 1;
  badge.style.display = 'flex';
}

function toggleNotifPanel() {
  // Reset badge when opened
  const badge = document.getElementById('notif-count');
  if (badge) { badge.textContent = '0'; badge.style.display = 'none'; }
}

async function signOut() {
  await edumeDB.sb.auth.signOut();
  window.location.href = '/index.html';
}

// ---- Loader utility ----
function setLoading(btn, loading, originalText) {
  if (loading) {
    btn.disabled = true;
    btn.innerHTML = `<span class="spinner" style="width:16px;height:16px;margin:0;border-width:2px"></span> Loading…`;
  } else {
    btn.disabled = false;
    btn.innerHTML = originalText;
  }
}

// ---- Format price in LKR ----
function formatLKR(amount) {
  return `LKR ${Number(amount).toLocaleString('en-LK')}`;
}

// ---- Format date ----
function formatDate(dateStr) {
  return new Date(dateStr).toLocaleDateString('en-LK', {
    year: 'numeric', month: 'short', day: 'numeric'
  });
}
