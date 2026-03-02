const { mapUser, findTrackedMessage, discord } = require('./helpers');

module.exports = async ({ github, context }) => {
  const pr = context.payload.pull_request;
  const reviewer = mapUser(context.payload.review.user.login);

  const tracked = await findTrackedMessage(github, context.repo, pr.number);
  if (!tracked) return;

  await discord('PATCH', `/messages/${tracked.msgId}`, {
    content: `Approved by ${reviewer}`,
    embeds: [
      {
        title: `READY TO MERGE: ${pr.title}`,
        url: pr.html_url,
        description: `PR #${pr.number} by ${mapUser(pr.user.login)}`,
        color: 3066993,
      },
    ],
  });
};
