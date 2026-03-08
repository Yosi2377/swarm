// Project port and URL mappings
// Single source of truth for sandbox/production URLs

const PROJECTS = {
  botverse: {
    name: 'BotVerse',
    path: '/root/BotVerse',
    sandbox: '/root/sandbox/BotVerse',
    service: 'botverse',
    sandboxService: 'sandbox-botverse',
    url: 'https://botverse.dev',
    sandboxUrl: 'http://95.111.247.22:9099',
    sandboxPort: 9099,
    productionPort: 4000,
    db: 'botverse',
    testCommand: 'bash tests/e2e.sh'
  },
  betting: {
    name: 'ZozoBet',
    path: '/root/BettingPlatform',
    sandbox: '/root/sandbox/BettingPlatform',
    service: 'betting-backend',
    sandboxService: 'sandbox-betting-backend',
    url: 'https://zozobet.com',
    sandboxUrl: 'http://95.111.247.22:9301',
    sandboxPort: 9301,
    productionPort: 8089,
    db: 'betting',
    testCommand: ''
  }
};

function getProject(nameOrPath) {
  const lower = (nameOrPath || '').toLowerCase();
  if (lower.includes('botverse') || lower.includes('bot')) return PROJECTS.botverse;
  if (lower.includes('betting') || lower.includes('zozo') || lower.includes('bet')) return PROJECTS.betting;
  return PROJECTS.botverse; // default
}

function getProjectConfig(nameOrPath) {
  return getProject(nameOrPath);
}

module.exports = { PROJECTS, getProject, getProjectConfig };
