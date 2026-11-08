// Gera a pasta public/ com o site + config.js (chaves vindas do .env ou da Vercel).
const fs = require('fs');
const path = require('path');

// Lê o .env local, se existir. Na Vercel, as variáveis já vêm do painel.
if (fs.existsSync('.env')) {
  for (const linha of fs.readFileSync('.env', 'utf8').split(/\r?\n/)) {
    const m = linha.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (m && !(m[1] in process.env)) {
      process.env[m[1]] = m[2].replace(/^['"]|['"]$/g, '');
    }
  }
}

const url = process.env.SUPABASE_URL;
const chave = process.env.SUPABASE_PUBLISHABLE_KEY;

if (!url || !chave) {
  console.error('ERRO: defina SUPABASE_URL e SUPABASE_PUBLISHABLE_KEY (no .env local ou nas variaveis da Vercel).');
  process.exit(1);
}

fs.rmSync('public', { recursive: true, force: true });
fs.mkdirSync('public');
fs.copyFileSync('index.html', path.join('public', 'index.html'));
fs.writeFileSync(
  path.join('public', 'config.js'),
  'window.CONFIG = ' + JSON.stringify({ SUPABASE_URL: url, SUPABASE_KEY: chave }) + ';\n'
);
console.log('Build ok: pasta public/ gerada.');
