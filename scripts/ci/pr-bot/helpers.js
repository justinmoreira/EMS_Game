const GITHUB_TO_DISCORD = {
  cjanua: '448167548010102794',
  justinmoreira: '693996087421173761',
  skyclo: '717468257107574804',
  alegarcia77: '1087739908317257848',
  // TODO: add Wenteng's GitHub username: '723329360832102460'
};

function mapUser(gh) {
  const id = GITHUB_TO_DISCORD[gh];
  return id ? `<@${id}>` : gh;
}

async function findTrackedMessage(github, repo, prNumber) {
  const { data: comments } = await github.rest.issues.listComments({
    ...repo,
    issue_number: prNumber,
  });
  const tracked = comments.find((c) => c.body.includes('<!-- discord-msg-id:'));
  if (!tracked) return null;
  const msgId = tracked.body.match(/<!-- discord-msg-id:(\d+) -->/)?.[1];
  return msgId ? { msgId, commentId: tracked.id } : null;
}

async function discord(method, path, body) {
  const opts = { method, headers: { 'Content-Type': 'application/json' } };
  if (body) opts.body = JSON.stringify({ allowed_mentions: { parse: ['users'] }, ...body });
  const res = await fetch(`${process.env.DISCORD_WEBHOOK_URL}${path}`, opts);
  return method === 'POST' ? res.json() : res;
}

module.exports = { mapUser, findTrackedMessage, discord };
