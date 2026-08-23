/* ==========================================================================
   NanoShell Docs - Interactive JavaScript Engine
   Created by Suman Biswas
   ========================================================================== */

document.addEventListener('DOMContentLoaded', () => {
  initTerminalTabs();
  initGlobalSearch();
  initSidebarFilter();
  initCopyButtons();
  initTelemetrySimulator();
  initScrollSpy();
});

/* 1. Terminal Tab Switcher */
function initTerminalTabs() {
  const tabs = document.querySelectorAll('.term-tab');
  const contents = document.querySelectorAll('.term-content');

  tabs.forEach(tab => {
    tab.addEventListener('click', () => {
      tabs.forEach(t => t.classList.remove('active'));
      contents.forEach(c => c.classList.remove('active'));

      tab.classList.add('active');
      const targetId = `tab-${tab.dataset.tab}`;
      const targetContent = document.getElementById(targetId);
      if (targetContent) targetContent.classList.add('active');
    });
  });
}

/* 2. Global Search & Ctrl+K Hotkey */
function initGlobalSearch() {
  const searchInput = document.getElementById('global-search');
  if (!searchInput) return;

  // Keyboard shortcut Ctrl + K
  window.addEventListener('keydown', (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key === 'k') {
      e.preventDefault();
      searchInput.focus();
    }
  });

  // Instant filter scroll on Enter or typing
  searchInput.addEventListener('input', (e) => {
    const query = e.target.value.toLowerCase().trim();
    if (!query) return;

    const cards = document.querySelectorAll('.api-card');
    cards.forEach(card => {
      const text = card.textContent.toLowerCase();
      if (text.includes(query)) {
        card.style.display = 'block';
      } else {
        card.style.display = 'none';
      }
    });
  });
}

/* 3. Sidebar Module Filter */
function initSidebarFilter() {
  const filterInput = document.getElementById('api-filter-input');
  const menuLinks = document.querySelectorAll('#api-menu a');

  if (!filterInput) return;

  filterInput.addEventListener('input', (e) => {
    const query = e.target.value.toLowerCase().trim();
    menuLinks.forEach(link => {
      const text = link.textContent.toLowerCase();
      if (text.includes(query)) {
        link.parentElement.style.display = 'block';
      } else {
        link.parentElement.style.display = 'none';
      }
    });
  });
}

/* 4. Copy Code Snippets to Clipboard */
function initCopyButtons() {
  const copyBtns = document.querySelectorAll('.btn-copy');

  copyBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      const codeBlock = btn.parentElement.nextElementSibling;
      if (!codeBlock) return;
      const text = codeBlock.textContent;

      navigator.clipboard.writeText(text).then(() => {
        const originalText = btn.textContent;
        btn.textContent = 'Copied! ✓';
        btn.style.background = '#10b981';
        btn.style.color = '#fff';

        setTimeout(() => {
          btn.textContent = originalText;
          btn.style.background = '';
          btn.style.color = '';
        }, 2000);
      });
    });
  });
}

/* 5. Hero Realtime Telemetry Simulation (RAM & FPS) */
function initTelemetrySimulator() {
  const ramEl = document.getElementById('hero-ram');
  const fpsEl = document.getElementById('hero-fps');

  if (!ramEl || !fpsEl) return;

  setInterval(() => {
    // Slight realistic hardware micro-fluctuations
    const ram = (17.1 + Math.random() * 0.3).toFixed(1);
    const fps = Math.floor(119 + Math.random() * 2);

    ramEl.textContent = `${ram} MB`;
    fpsEl.textContent = `${fps} FPS`;
  }, 1500);
}

/* 6. ScrollSpy for Sidebar Active State */
function initScrollSpy() {
  const sections = document.querySelectorAll('.api-card');
  const menuLinks = document.querySelectorAll('#api-menu a');

  window.addEventListener('scroll', () => {
    let current = '';
    sections.forEach(section => {
      const sectionTop = section.offsetTop - 120;
      if (window.scrollY >= sectionTop) {
        current = section.getAttribute('id');
      }
    });

    menuLinks.forEach(link => {
      link.classList.remove('active');
      if (link.getAttribute('href') === `#${current}`) {
        link.classList.add('active');
      }
    });
  });
}
