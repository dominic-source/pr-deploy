#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
# set -e

comment() {
    local status_message=$1
    local preview_url=$2

    local comment_body=$(jq -n --arg body "<strong>Here are the latest updates on your deployment.</strong> Explore the action and ⭐ star our project for more insights! 🔍
<table>
  <thead>
    <tr>
      <th>Deployed By</th>
      <th>Status</th>
      <th>Preview URL</th>
      <th>Updated At (UTC)</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><a href='https://github.com/hngprojects/pr-deploy'>PR Deploy</a></td>
      <td>${status_message}</td>
      <td><a href='${preview_url}'>Visit Preview</a></td>
      <td>$(date +'%b %d, %Y %I:%M%p')</td>
    </tr>  
  </tbody>
</table>" '{body: $body}')

    if [ -z "$COMMENT_ID" ]; then
        # Create a new comment
        COMMENT_ID=$(curl -s -H "Authorization: token $GITHUB_TOKEN" -X POST \
            -d "$comment_body" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/issues/${PR_NUMBER}/comments" | jq -r '.id')
    else
        # Update an existing comment
        curl -s -H "Authorization: token $GITHUB_TOKEN" -X PATCH \
            -d "$comment_body" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/issues/comments/${COMMENT_ID}" > /dev/null
    fi
}

REPO_ID=$(curl -L \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME} | jq -r '.id')

# Make the pr-deploy.sh script executable.
chmod +x pr-deploy.sh

# Checks if the action is opened
if [ "$PR_ACTION" == "opened" ]; then
  comment "Deploying ⏳" "#"
fi

# Copy the pr-deploy.sh script to the remote server.
sshpass -p "$SERVER_PASSWORD" scp -o StrictHostKeyChecking=no -P $SERVER_PORT ./pr-deploy.sh $SERVER_USERNAME@$SERVER_HOST:/srv/pr-deploy.sh

# Run the pr-deploy.sh script on the remote server and capture the output from the remote script
REMOTE_OUTPUT=$(sshpass -p "$SERVER_PASSWORD" ssh -o StrictHostKeyChecking=no -p $SERVER_PORT $SERVER_USERNAME@$SERVER_HOST /srv/pr-deploy.sh $CONTEXT $DOCKERFILE $EXPOSED_PORT $REPO_URL $REPO_ID $GITHUB_HEAD_REF $PR_ACTION $PR_NUMBER $COMMENT_ID | tail -n 1)

# Debug the raw output
echo "Raw Remote Output: $REMOTE_OUTPUT"

# Ensure the output is valid JSON by escaping problematic characters
SANITIZED_OUTPUT=$(echo "$REMOTE_OUTPUT" | sed 's/[[:cntrl:]]//g')

# Parse the sanitized JSON
COMMENT_ID=$(echo "$SANITIZED_OUTPUT" | jq -r '.COMMENT_ID')
DEPLOYED_URL=$(echo "$SANITIZED_OUTPUT" | jq -r '.DEPLOYED_URL')

echo "Comment ID: $COMMENT_ID"
echo "Deployed URL: $DEPLOYED_URL"

if [  -z "$DEPLOYED_URL" ]; then
    comment "Failed ❌" "#"
elif [ "$PR_ACTION" == "closed" ]; then
    comment "Terminated 🛑" "#"
else
    comment "Deployed 🎉" $DEPLOYED_URL
fi
