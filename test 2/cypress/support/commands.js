// ***********************************************
// This example commands.js shows you how to
// create various custom commands and overwrite
// existing commands.
//
// For more comprehensive examples of custom
// commands please read more here:
// https://on.cypress.io/custom-commands
// ***********************************************

// Custom command to wait for app to be ready
Cypress.Commands.add('waitForApp', () => {
  cy.get('[data-testid="app-title"]', { timeout: 10000 }).should('be.visible')
})

// Custom command to reset app state
Cypress.Commands.add('resetApp', () => {
  cy.get('[data-testid="reset-btn"]').click()
  cy.get('[data-testid="message-input"]').clear().type('Hello Coursera!')
})
