# Testing Guide

Cypress is a powerful, open-source testing framework used for end-to-end testing of web applications. It provides a rich set of features for writing and running tests, making it easier to ensure the quality and reliability of your web applications.

The provided tests are basic functionality test that assume a certain structure of your application. Feel free to edit the files in the `cypress` directory to customize your tests!

## Types of Tests

- **End-to-End (E2E) Testing**: These tests simulate real user interactions in the browser to ensure your application behaves as expected.
- **Component Testing**: This involves testing individual components in isolation to verify their functionality.

## Running Tests

To run Cypress tests in this project, follow these steps:

1. **Install Cypress**: Run the following command to install Cypress as a development dependency:
   ```bash
   npm install -D cypress @cypress/react
   ```

2. **Add Script to `package.json`**: Add the following line to the `scripts` section of your `package.json`:
   ```json
    "test": "eslint src && cypress run --component && cypress run --e2e",
   ```

3. **Run Tests**: Run the following command to run all the tests:

First start the development server:
```bash
PORT=8181 npm run dev
```

Then run the tests:
```bash
PORT=8181 npm run test
```

If you want to open cypress in the browser you can run:

```bash
PORT=8181 cypress open
```

*Note: Note the PORT numbers above, this is simply to make sure the dev server is running on the same port as the tests.*

**If you run into an error where cypress can't connect to your dev server you may need to add this section to your `vite.config.js` to make sure it reads in the PORT environment variable.**

```js
  server: {
    port: process.env.PORT || 8080,
  },
```

By following these steps, you can set up and run Cypress tests to try out your application automatically! 