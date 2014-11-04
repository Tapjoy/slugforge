## 4.1.4 (November 4, 2014)

Changes:
  - Provide a useful message if the slug bucket is invalid.
  - Return faster if no slugs will be purged by wrangler purge
  - Reduce JSON output from aws s3 cp commands, unless --verbose is specified.
  - Ensure that staged slugs do not report failures in JSON output
  - Update the tag pattern matcher to support regex's
  - Succeed if `tag delete` tries to delete a tag that doesn't exist
  - Ensure that `tag delete --json` does not prompt, and that it returns JSON
  - Add the `wrangler lookup [name_part]` command
  - Add install.completed notification at completion of each host install. This allows subscription for slugins/post deploy actions.
  - Fix `slugforge pry` command for use with Ruby 2+
  - Make `slugforge debug` command always print the result of the command
  - Refactor @deploy_results and SSH_COMMAND_EXIT_CODE into ssh_command
  - Updates to required gem versions
  - Minor bug fixes

## 4.0.1 (August 17, 2014)

Changes:
  - Support the force flag when installing slugs
  - Fix a bug with the post install script that could generate errors
