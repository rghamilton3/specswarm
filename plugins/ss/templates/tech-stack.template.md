# Tech Stack - [PROJECT_NAME]

**Last Updated**: [DATE]
**Auto-Generated**: [AUTO_GENERATED]

<!--
  Sections wrapped in the `ss:user-additions` ... `ss:end` HTML comment markers
  (see below) are preserved verbatim when /ss:init is re-run. Edit freely inside
  those blocks. The rest of the file is regenerated from project detection on
  each /ss:init.
-->

---

## Core Technologies

### Framework
- **[FRAMEWORK]** [FRAMEWORK_VERSION]
  - Notes: [FRAMEWORK_NOTES]

### Language
- **[LANGUAGE]** [LANGUAGE_VERSION]
  - Notes: [LANGUAGE_NOTES]

### Build Tool
- **[BUILD_TOOL]** [BUILD_TOOL_VERSION]
  - Notes: [BUILD_TOOL_NOTES]

---

## State Management

[STATE_MANAGEMENT_SECTION]

---

## Styling

[STYLING_SECTION]

---

## Testing

### Unit Testing
- **[UNIT_TEST_FRAMEWORK]** [UNIT_TEST_VERSION]
  - Purpose: Component and function unit tests

### Integration Testing
- **[INTEGRATION_TEST_FRAMEWORK]** [INTEGRATION_TEST_VERSION]
  - Purpose: API and integration tests

### End-to-End Testing
- **[E2E_TEST_FRAMEWORK]** [E2E_TEST_VERSION]
  - Purpose: Full application flow testing

---

## Approved Libraries

[APPROVED_LIBRARIES_SECTION]

<!-- ss:user-additions -->
<!-- Add project-specific approved libraries below. Content here is preserved on /ss:init re-run. -->
<!-- ss:end -->

---

## Prohibited Technologies

The following technologies/patterns are **NOT** approved for this project:

[PROHIBITED_SECTION]

<!-- ss:user-additions -->
<!-- Add project-specific prohibited patterns below. Content here is preserved on /ss:init re-run. -->
<!-- ss:end -->

---

## Guidelines

### Adding New Dependencies

Before adding a new dependency:
1. Check if existing approved libraries can solve the problem
2. Verify the library is actively maintained
3. Check bundle size impact
4. Ensure TypeScript support (if applicable)
5. Get team approval for major dependencies

### Version Updates

- Follow semver for all dependencies
- Test thoroughly before updating major versions
- Document breaking changes in this file
- Update CI/CD pipelines if needed

---

## Notes

[NOTES_SECTION]

<!-- ss:user-additions -->
<!-- Add project-specific notes below. Content here is preserved on /ss:init re-run. -->
<!-- ss:end -->

---

**Tech Stack Enforcement**: This file is used by SpecSwarm to prevent technology drift. Commands like `/ss:build` and `/ss:implement` will reference this file to ensure consistency across features.
