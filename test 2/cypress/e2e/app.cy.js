describe('Coursera React Lab E2E Tests', () => {
  beforeEach(() => {
    cy.visit('/')
  })

  it('should load the application successfully', () => {
    cy.get('[data-testid="app-title"]').should('be.visible')
    cy.get('[data-testid="app-title"]').should('contain', 'Coursera React Lab')
  })

  it('should test counter functionality', () => {
    // Test initial state
    cy.get('[data-testid="counter-value"]').should('contain', '0')
    
    // Test increment
    cy.get('[data-testid="increment-btn"]').click()
    cy.get('[data-testid="counter-value"]').should('contain', '1')
    
    // Test multiple increments
    cy.get('[data-testid="increment-btn"]').click().click()
    cy.get('[data-testid="counter-value"]').should('contain', '3')
    
    // Test decrement
    cy.get('[data-testid="decrement-btn"]').click()
    cy.get('[data-testid="counter-value"]').should('contain', '2')
    
    // Test reset
    cy.get('[data-testid="reset-btn"]').click()
    cy.get('[data-testid="counter-value"]').should('contain', '0')
  })

  it('should test message input functionality', () => {
    // Test initial message
    cy.get('[data-testid="message-display"]').should('contain', 'Hello Coursera!')
    
    // Test message change
    cy.get('[data-testid="message-input"]').clear().type('Testing E2E')
    cy.get('[data-testid="message-display"]').should('contain', 'Testing E2E')
    
    // Test empty message
    cy.get('[data-testid="message-input"]').clear()
    cy.get('[data-testid="message-display"]').should('contain', '')
  })

  it('should test list management functionality', () => {
    // Test initial items
    cy.get('[data-testid="item-list"]').should('contain', 'Item 1')
    cy.get('[data-testid="item-list"]').should('contain', 'Item 2')
    cy.get('[data-testid="item-list"]').should('contain', 'Item 3')
    
    // Test adding items
    cy.get('[data-testid="add-item-btn"]').click()
    cy.get('[data-testid="item-list"]').should('contain', 'Item 4')
    
    cy.get('[data-testid="add-item-btn"]').click()
    cy.get('[data-testid="item-list"]').should('contain', 'Item 5')
    
    // Test removing items
    cy.get('[data-testid="remove-item-0"]').click()
    cy.get('[data-testid="item-list"]').should('not.contain', 'Item 1')
    
    // Verify remaining items
    cy.get('[data-testid="item-list"]').should('contain', 'Item 2')
    cy.get('[data-testid="item-list"]').should('contain', 'Item 3')
    cy.get('[data-testid="item-list"]').should('contain', 'Item 4')
    cy.get('[data-testid="item-list"]').should('contain', 'Item 5')
  })

  it('should test complete user workflow', () => {
    // Counter workflow
    cy.get('[data-testid="increment-btn"]').click().click().click()
    cy.get('[data-testid="counter-value"]').should('contain', '3')
    
    // Message workflow
    cy.get('[data-testid="message-input"]').clear().type('Workflow Test')
    cy.get('[data-testid="message-display"]').should('contain', 'Workflow Test')
    
    // List workflow
    cy.get('[data-testid="add-item-btn"]').click().click()
    cy.get('[data-testid="remove-item-0"]').click()
    
    // Verify final state
    cy.get('[data-testid="counter-value"]').should('contain', '3')
    cy.get('[data-testid="message-display"]').should('contain', 'Workflow Test')
    cy.get('[data-testid="item-list"]').should('contain', 'Item 2')
    cy.get('[data-testid="item-list"]').should('contain', 'Item 3')
    cy.get('[data-testid="item-list"]').should('contain', 'Item 4')
    cy.get('[data-testid="item-list"]').should('contain', 'Item 5')
  })

  it('should verify all buttons are clickable', () => {
    cy.get('[data-testid="increment-btn"]').should('be.visible').and('not.be.disabled')
    cy.get('[data-testid="decrement-btn"]').should('be.visible').and('not.be.disabled')
    cy.get('[data-testid="reset-btn"]').should('be.visible').and('not.be.disabled')
    cy.get('[data-testid="add-item-btn"]').should('be.visible').and('not.be.disabled')
    
    // Test that buttons actually work
    cy.get('[data-testid="increment-btn"]').click()
    cy.get('[data-testid="counter-value"]').should('contain', '1')
    
    cy.get('[data-testid="add-item-btn"]').click()
    cy.get('[data-testid="item-list"]').should('contain', 'Item 4')
  })
})
