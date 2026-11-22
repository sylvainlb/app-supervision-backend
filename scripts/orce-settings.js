// Node-RED settings of the energy-supervision deployment (copied to /data/settings.js at boot).
// Identical to the FAP-light core settings, with httpAdminRoot '/editor':
// the LDP middleware (fap-ldp-container) serves the root '/', it excludes '/editor' →
// the Node-RED editor is reachable on https://<pod>/editor/ (see caddy/Caddyfile).
// functionExternalModules: true allows function node libs (pg, crypto…).
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
