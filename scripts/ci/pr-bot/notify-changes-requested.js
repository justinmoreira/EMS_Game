const { mapUser, findTrackedMessage, discord } = require('./helpers');

module.exports = async ({ github, context }) => {
  const pr = context.payload.pull_request;
  const reviewer = context.payload.review.user.login;
  const author = mapUser(pr.user.login);

  const tracked = await findTrackedMessage(github, context.repo, pr.number);
  if (!tracked) return;

  await discord('PATCH', `/messages/${tracked.msgId}`, {
    content: `${author} you have Requested Changes from ${reviewer}`,
    embeds: [
      {
        title: `CHANGES REQUESTED: ${pr.title}`,
        url: pr.html_url,
        description: `PR #${pr.number} by ${author}`,
        color: 15158332,
      },
    ],
  });
};
