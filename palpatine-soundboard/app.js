const board = document.getElementById('board');
const statusEl = document.getElementById('status');

let current = null;      // the <audio> that is playing
let currentBtn = null;

function stopCurrent() {
  if (!current) return;
  current.pause();
  current.currentTime = 0;
  if (currentBtn) currentBtn.classList.remove('playing');
  current = null;
  currentBtn = null;
}

function makeButton(entry) {
  const btn = document.createElement('button');
  btn.textContent = entry.label;

  const audio = new Audio(entry.file);
  audio.preload = 'auto';
  audio.addEventListener('ended', stopCurrent);

  // The tap handler stays fully synchronous: iOS only honours .play()
  // when it is reached directly from the user gesture, never after an await.
  btn.addEventListener('click', () => {
    const again = current === audio;
    stopCurrent();
    if (again) return;           // second tap on the same button = stop

    audio.currentTime = 0;
    const p = audio.play();
    current = audio;
    currentBtn = btn;
    btn.classList.add('playing');
    if (p) p.catch(() => { stopCurrent(); btn.disabled = true; });
  });

  return btn;
}

async function init() {
  let sounds;
  try {
    const res = await fetch('sounds.json', { cache: 'no-store' });
    if (!res.ok) throw new Error('HTTP ' + res.status);
    sounds = await res.json();
  } catch (err) {
    statusEl.textContent = 'Could not load sounds.json: ' + err.message;
    return;
  }

  const buttons = sounds.map(entry => {
    const btn = makeButton(entry);
    board.appendChild(btn);
    return { btn, entry };
  });

  // Disable buttons whose clip is not on disk yet, rather than letting the
  // tap fail silently. HEAD works before any user gesture, unlike media load.
  let missing = 0;
  await Promise.all(buttons.map(async ({ btn, entry }) => {
    try {
      const res = await fetch(entry.file, { method: 'HEAD', cache: 'no-store' });
      if (!res.ok) throw new Error();
    } catch {
      btn.disabled = true;
      btn.textContent = entry.label + ' (no clip)';
      missing++;
    }
  }));

  statusEl.textContent = missing
    ? missing + ' of ' + buttons.length + ' clips missing from /audio'
    : '';
}

init();
