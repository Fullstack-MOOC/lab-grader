/* eslint-disable import/no-extraneous-dependencies */
import React from 'react';
import { mount } from 'cypress/react';
import SearchBar from '../../src/components/search_bar';

context('SearchBar Component', () => {
  it('renders the SearchBar component', () => {
    mount(<SearchBar onSearchChange={() => { }} />);
    cy.get('#search-bar').should('exist');
  });

  it('calls onSearchChange on input change', () => {
    const onSearchChangeSpy = cy.spy().as('onSearchChangeSpy');
    mount(<SearchBar onSearchChange={onSearchChangeSpy} />);
    cy.get('input').type('test');
    cy.get('@onSearchChangeSpy').should('have.been.calledWith', 'test');
  });
});
