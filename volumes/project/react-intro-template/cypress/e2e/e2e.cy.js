/* eslint-disable cypress/unsafe-to-chain-command */
describe('Testing for React Intro Lab', () => {
  beforeEach(() => {
    cy.visit('/'); // may need changing to match route
    cy.get('input')
      .type('spooked and confused')
      .should('have.value', 'spooked and confused');
  });

  it('should update video list when typing in the search bar', () => {
    cy.get('#video-list > li')
      .first()
      .should('contain.text', 'Spooked And Confused');
  });

  it('should update video detail when typing in the search bar', () => {
    cy.get('#video-detail')
      .should('contain.text', 'Spooked And Confused');
  });
});
