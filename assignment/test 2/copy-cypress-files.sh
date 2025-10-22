#!/bin/bash

# Script to copy Cypress test files to another location
# Usage: ./copy-cypress-files.sh /path/to/destination

if [ $# -eq 0 ]; then
    echo "Usage: $0 <destination_path>"
    echo "Example: $0 /home/coder/project/react-intro-template"
    exit 1
fi

DEST_PATH="$1"

echo "Copying Cypress files to: $DEST_PATH"

# Create directories if they don't exist
mkdir -p "$DEST_PATH/cypress/e2e"
mkdir -p "$DEST_PATH/cypress/support"

# Copy the essential files
cp package.json "$DEST_PATH/"
cp cypress.config.js "$DEST_PATH/"
cp cypress/e2e/simple-test.cy.js "$DEST_PATH/cypress/e2e/"
cp cypress/support/e2e.js "$DEST_PATH/cypress/support/"

echo "Files copied successfully!"
echo "Now run: cd $DEST_PATH && npm install && npm test"
