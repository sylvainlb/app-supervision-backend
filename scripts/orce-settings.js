// Settings Node-RED du déploiement energy-supervision (copié sur /data/settings.js au boot).
// Identique au settings du cœur FAP-light, avec httpAdminRoot '/editor' :
// le middleware LDP (fap-ldp-container) sert la racine '/', il exclut '/editor' →
// l'éditeur Node-RED est joignable sur https://<pod>/editor/ (voir caddy/Caddyfile).
// functionExternalModules: true autorise les libs des function nodes (pg, crypto…).
module.exports = {
  flowFile: 'flows.json',
  userDir: '/data',
  httpAdminRoot: '/editor',
  httpNodeRoot: '/',
  uiPort: process.env.PORT || 1880,
  functionExternalModules: true,
  functionTimeout: 30000,
  httpNodeCors: { origin: '*' },
  credentialSecret: process.env.NODE_RED_CREDENTIAL_SECRET || 'fap-light-credential-secret',
  logging: {
    console: { level: 'info', metrics: false, audit: false }
  }
};
