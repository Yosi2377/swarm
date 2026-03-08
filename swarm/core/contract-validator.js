// Contract Validator — returns specific errors for invalid contracts

const { TASK_TYPES } = require('./contract-templates');

function validateContract(contract) {
  const errors = [];

  if (!contract || typeof contract !== 'object') {
    return { valid: false, errors: ['Contract must be a non-null object'] };
  }

  // Required top-level fields
  if (!contract.id) errors.push('Missing required field: id');
  if (!contract.type) {
    errors.push('Missing required field: type');
  } else if (!TASK_TYPES.includes(contract.type)) {
    errors.push(`Invalid task type: "${contract.type}". Must be one of: ${TASK_TYPES.join(', ')}`);
  }

  // Input validation
  if (!contract.input) {
    errors.push('Missing required field: input');
  } else {
    if (!contract.input.description) errors.push('Missing required field: input.description');
  }

  // Expected artifacts
  if (!contract.expected_artifacts) {
    errors.push('Missing required field: expected_artifacts');
  } else {
    if (!Array.isArray(contract.expected_artifacts.files_changed)) {
      errors.push('expected_artifacts.files_changed must be an array');
    }
  }

  // Acceptance criteria
  if (!contract.acceptance_criteria) {
    errors.push('Missing required field: acceptance_criteria');
  } else if (!Array.isArray(contract.acceptance_criteria)) {
    errors.push('acceptance_criteria must be an array');
  } else if (contract.acceptance_criteria.length === 0) {
    errors.push('acceptance_criteria must have at least one criterion');
  } else {
    contract.acceptance_criteria.forEach((c, i) => {
      if (!c.type) errors.push(`acceptance_criteria[${i}] missing type`);
      if (!c.description) errors.push(`acceptance_criteria[${i}] missing description`);
    });
  }

  // Rollback
  if (!contract.rollback) {
    errors.push('Missing required field: rollback');
  } else if (!contract.rollback.strategy) {
    errors.push('Missing required field: rollback.strategy');
  }

  // Metadata
  if (!contract.metadata) {
    errors.push('Missing required field: metadata');
  } else {
    if (!contract.metadata.priority) errors.push('Missing required field: metadata.priority');
  }

  return { valid: errors.length === 0, errors };
}

module.exports = { validateContract };
