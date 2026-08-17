import{t as e}from"./games-jVKFmNjI.js";var t=document.querySelector(`#app`);if(!t)throw Error(`App root not found`);t.innerHTML=`
  <main class="catalog">
    <header class="catalog-header">
      <p class="eyebrow">Fiddlesticks Arcade</p>
      <h1>Choose your next game</h1>
      <p class="subtitle">Search instantly across the full collection and jump in.</p>
      <label class="search-wrap" for="game-search">
        <span class="visually-hidden">Search games</span>
        <input id="game-search" type="search" placeholder="Search by title, genre, or mood..." autocomplete="off" />
      </label>
      <p id="results-count" class="results-count" aria-live="polite"></p>
    </header>

    <ul id="game-list" class="game-list" aria-label="Games list"></ul>
  </main>
`;var n=document.querySelector(`#game-search`),r=document.querySelector(`#game-list`),i=document.querySelector(`#results-count`);if(!n||!r||!i)throw Error(`Required UI elements are missing`);function a(e){return e.toLowerCase().replace(/[^a-z0-9]+/g,`-`).replace(/(^-|-$)/g,``)}function o(t){let n=t.trim().toLowerCase(),o=e.filter(e=>[e.title,e.genre,e.description].some(e=>e.toLowerCase().includes(n)));if(i.textContent=`${o.length} of ${e.length} games`,o.length===0){r.innerHTML=`
      <li class="empty-state" role="status">
        <h2>No games found</h2>
        <p>Try a broader search like "puzzle" or "party".</p>
      </li>
    `;return}r.innerHTML=o.map(e=>{let t=a(e.title);return`
        <li class="game-card">
          <a class="game-link" href="/game.html?game=${encodeURIComponent(t)}">
            <div>
              <p class="genre">${e.genre}</p>
              <h2>${e.title}</h2>
              <p>${e.description}</p>
            </div>
            <span class="play-cta">Play</span>
          </a>
        </li>
      `}).join(``)}n.addEventListener(`input`,()=>{o(n.value)}),o(``);