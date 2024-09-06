#!/bin/bash

# Configuration variables
# Configuration variables
REPO_OWNER="ANSANJAY"                 # Your GitHub organization/username
REPO_NAME="test"                      # The name of your repository
SOURCE_BRANCH="test_branch"           # The branch containing the changes
TARGET_BRANCH="main"                  # The branch you are merging into
PR_TITLE="Automated SonarQube Integration"
PR_BODY="This PR includes updates from SonarQube analysis integration."

TARGET_BRANCH="main"             # The branch you are merging into
PR_TITLE="Automated SonarQube Integration"
PR_BODY="This PR includes updates from SonarQube analysis integration."

# Check if GitHub CLI is installed
if ! command -v gh &> /dev/null; then
    echo "GitHub CLI (gh) is not installed. Please install it to proceed."
    exit 1
fi

# Authenticate with GitHub if not already authenticated
if ! gh auth status &> /dev/null; then
    echo "Please authenticate with GitHub CLI using: gh auth login --hostname github.com"
    exit 1
fi

# Step 1: Check for existing PRs from the specified branch
check_existing_prs() {
    echo "Checking for existing PRs from branch $SOURCE_BRANCH..."
    existing_prs=$(gh pr list --repo "$REPO_OWNER/$REPO_NAME" --head "$SOURCE_BRANCH" --json number,title --jq '.[] | .number + " - " + .title')
    if [[ -n "$existing_prs" ]]; then
        echo "Existing PRs found from branch $SOURCE_BRANCH:"
        echo "$existing_prs"
    else
        echo "No existing PRs found for branch $SOURCE_BRANCH."
    fi
}

# Step 2: Check if the specified branch exists in the remote repository
check_branch_exists() {
    echo "Checking if the branch $SOURCE_BRANCH exists in the remote repository..."
    branch_exists=$(gh api repos/"$REPO_OWNER"/"$REPO_NAME"/branches/"$SOURCE_BRANCH" --silent || echo "false")
    if [[ "$branch_exists" == "false" ]]; then
        echo "Branch $SOURCE_BRANCH does not exist in the remote repository."
        exit 1
    else
        echo "Branch $SOURCE_BRANCH exists."
    fi
}

# Step 3: Create a new Pull Request if no PR is open with the same branch
create_pull_request() {
    echo "Creating a new pull request from $SOURCE_BRANCH to $TARGET_BRANCH..."
    pr_url=$(gh pr create --repo "$REPO_OWNER/$REPO_NAME" \
        --title "$PR_TITLE" \
        --body "$PR_BODY" \
        --head "$SOURCE_BRANCH" \
        --base "$TARGET_BRANCH")
    
    if [[ $? -eq 0 && -n "$pr_url" ]]; then
        echo "Pull request created successfully: $pr_url"
    else
        echo "Failed to create pull request."
        exit 1
    fi
}

# Inform the end user about changes made with dynamic file listing
inform_end_user() {
    echo "Gathering list of changed files and detailed line changes for notification..."

    # Get the list of changed files
    changed_files=$(gh pr view "$pr_url" --repo "$REPO_OWNER/$REPO_NAME" --json files --jq '.files | map(.path) | join("\n")')
    echo "Changed files: $changed_files"  # Debug statement

    # Fetch the complete diff of the PR
    pr_diff=$(gh pr diff "$pr_url" --repo "$REPO_OWNER/$REPO_NAME")
    echo "PR Diff: $pr_diff"  # Debug statement

    # Initialize the notification message
    CHANGE_NOTIFICATION="### Automated PR Changes Summary<br><br>"
    CHANGE_NOTIFICATION+="This PR includes changes to the following files:<br><br>"

    # Iterate through each changed file and extract the changes
    while IFS= read -r file; do
        echo "Processing file: $file"  # Debug statement

        # Extract the specific diff section for this file
        file_diff=$(echo "$pr_diff" | awk "/^diff --git a\/$file/,/^diff --git/ {print}" | grep -v "^diff --git" | grep -v "^index" | grep -v "^---" | grep -v "^\+\+\+")
        echo "File-specific diff for $file:"  # Debug statement
        echo "$file_diff"

        # Extract added lines for this specific file using extended regex to handle the + symbol
        added_lines=$(echo "$file_diff" | grep -E "^\\+[^+]" | sed 's/^+//')
        # Extract removed lines for this specific file using extended regex to handle the - symbol
        removed_lines=$(echo "$file_diff" | grep -E "^-[^-]" | sed 's/^-//')

        # Debug prints to verify extracted lines
        echo "Added lines for $file: $added_lines"  # Debug statement
        echo "Removed lines for $file: $removed_lines"  # Debug statement

        # Append the file header to the notification
        CHANGE_NOTIFICATION+="**File**: \`$file\`<br>"

        # Check if there are added lines and append them
        if [[ -n "$added_lines" ]]; then
            CHANGE_NOTIFICATION+="  - **Lines Added**:<br>"
            while IFS= read -r line; do
                CHANGE_NOTIFICATION+="    - \`${line}\`<br>"
            done <<< "$added_lines"
        fi

        # Check if there are removed lines and append them
        if [[ -n "$removed_lines" ]]; then
            CHANGE_NOTIFICATION+="  - **Lines Removed**:<br>"
            while IFS= read -r line; do
                CHANGE_NOTIFICATION+="    - \`${line}\`<br>"
            done <<< "$removed_lines"
        fi

        # Add an extra newline between files for clarity
        CHANGE_NOTIFICATION+="<br>"

    done <<< "$changed_files"

    # Final notification body with additional context
    CHANGE_NOTIFICATION+="These changes were made to integrate SonarQube analysis and modify build configurations where necessary.<br> Please review these changes and contact the team if you have any questions or concerns.<br>"

    # Post the notification comment to the PR
    if [[ -n "$changed_files" ]]; then
        echo "Informing end users about the changes made..."
        echo "Final notification content: $CHANGE_NOTIFICATION"  # Debug statement
        gh pr comment "$pr_url" --repo "$REPO_OWNER/$REPO_NAME" --body "$CHANGE_NOTIFICATION"
        echo "Notification comment added to the PR."
    else
        echo "No files were changed, skipping notification."
    fi
}

# Run the workflow
check_existing_prs    # Check for existing PRs from the branch
check_branch_exists   # Check if the branch exists in the remote repository
create_pull_request   # Create a new PR if applicable
inform_end_user       # Inform the end user about the changes made with dynamic file listing
