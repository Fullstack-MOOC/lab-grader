describe('Simple Test Suite', () => {
  it('should always pass', () => {
    // This test will always pass
    expect(true).to.be.true;
  });

  it('should verify basic math', () => {
    // Another simple test that will always pass
    expect(2 + 2).to.equal(4);
  });

  it('should check string equality', () => {
    // Test string comparison
    expect('hello').to.equal('hello');
  });
});
