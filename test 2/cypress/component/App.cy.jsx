import React from 'react'
import App from '../../src/App'

describe('App Component Tests', () => {
  beforeEach(() => {
    cy.mount(<App />)
  })

  it('renders main title', () => {
    cy.get('[data-testid="app-title"]').should('be.visible')
    cy.get('[data-testid="app-title"]').should('contain', 'Coursera React Lab')
  })

  it('displays initial counter value', () => {
    cy.get('[data-testid="counter-value"]').should('contain', '0')
  })

  it('increments counter', () => {
    cy.get('[data-testid="increment-btn"]').click()
    cy.get('[data-testid="counter-value"]').should('contain', '1')
    
    cy.get('[data-testid="increment-btn"]').click()
    cy.get('[data-testid="counter-value"]').should('contain', '2')
  })

  it('decrements counter', () => {
    // First increment to have something to decrement
    cy.get('[data-testid="increment-btn"]').click().click()
    cy.get('[data-testid="counter-value"]').should('contain', '2')
    
    cy.get('[data-testid="decrement-btn"]').click()
    cy.get('[data-testid="counter-value"]').should('contain', '1')
  })

  it('resets counter', () => {
    // First increment to have something to reset
    cy.get('[data-testid="increment-btn"]').click().click().click()
    cy.get('[data-testid="counter-value"]').should('contain', '3')
    
    cy.get('[data-testid="reset-btn"]').click()
    cy.get('[data-testid="counter-value"]').should('contain', '0')
  })

  it('displays initial message', () => {
    cy.get('[data-testid="message-display"]').should('contain', 'Hello Coursera!')
  })

  it('updates message on input change', () => {
    cy.get('[data-testid="message-input"]').clear().type('New Message')
    cy.get('[data-testid="message-display"]').should('contain', 'New Message')
  })

  it('displays initial list items', () => {
    cy.get('[data-testid="item-list"]').should('contain', 'Item 1')
    cy.get('[data-testid="item-list"]').should('contain', 'Item 2')
    cy.get('[data-testid="item-list"]').should('contain', 'Item 3')
  })

  it('adds new items', () => {
    cy.get('[data-testid="add-item-btn"]').click()
    cy.get('[data-testid="item-list"]').should('contain', 'Item 4')
    
    cy.get('[data-testid="add-item-btn"]').click()
    cy.get('[data-testid="item-list"]').should('contain', 'Item 5')
  })

  it('removes items', () => {
    cy.get('[data-testid="remove-item-0"]').click()
    cy.get('[data-testid="item-list"]').should('not.contain', 'Item 1')
    
    // Verify remaining items
    cy.get('[data-testid="item-list"]').should('contain', 'Item 2')
    cy.get('[data-testid="item-list"]').should('contain', 'Item 3')
  })
})
