// eslint-disable-next-line import/no-extraneous-dependencies
import { defineConfig } from 'cypress';
import { GenerateCtrfReport } from 'cypress-ctrf-json-reporter';

const baseUrl = process.env.PORT
  ? `http://localhost:${process.env.PORT}`
  : 'http://localhost:8080';

// Add your baseUrl definition here
export default defineConfig({
  e2e: {
    baseUrl,
    video: false,
    supportFile: false,
    screenshotOnRunFailure: false,
    specPattern: 'cypress/e2e/*.cy.{js,jsx,ts,tsx}',
    // Memory management settings
    experimentalMemoryManagement: true,
    numTestsKeptInMemory: 0,
    setupNodeEvents(on, config) {
      // Generate separate reports for each test type
      new GenerateCtrfReport({
        outputDir: 'results',
        outputFile: 'e2e_feedback.json',
        on,
      });
    },
  },
  component: {
    video: false,
    supportFile: false,
    screenshotOnRunFailure: false,
    specPattern: 'cypress/component/*.cy.{js,jsx,ts,tsx}',
    // Memory management settings
    experimentalMemoryManagement: true,
    numTestsKeptInMemory: 0,
    devServer: {
      framework: 'react',
      bundler: 'vite',
      indexHtml: 'cypress/support/component-index.html',
    },
    setupNodeEvents(on, config) {
      // Generate separate reports for each test type
      new GenerateCtrfReport({
        outputDir: 'results',
        outputFile: 'component_feedback.json',
        on,
      });
    },
  },
});