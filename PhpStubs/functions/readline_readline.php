<?php

/**
 * Reads a line
 * @param string|null $prompt [optional] You may specify a string with which to prompt the user.
 * @return string|false a single string from the user. The line returned has the ending newline removed. If there is no more data to read, then FALSE is returned.
 */
function readline(?string $prompt = null): string|false {}

/**
 * Gets/sets various internal readline variables
 * @param string|null $var_name [optional] A variable name.
 * @param string $value [optional] If provided, this will be the new value of the setting.
 * @return mixed If called with no parameters, this function returns an array of values for all the setting readline uses. The elements will be indexed by the following values: done, end, erase_empty_line, library_version, line_buffer, mark, pending_input, point, prompt, readline_name, and ...
 */
function readline_info(?string $var_name = null, $value = null): mixed {}

/**
 * Adds a line to the history
 * @param string $prompt The line to be added in the history.
 * @return bool TRUE on success or FALSE on failure.
 */
function readline_add_history(string $prompt): bool {}

/**
 * Clears the history
 * @return bool TRUE on success or FALSE on failure.
 */
function readline_clear_history(): bool {}

/**
 * Lists the history
 * @return array an array of the entire command line history. The elements are indexed by integers starting at zero.
 */
function readline_list_history(): array {}

/**
 * Reads the history
 * @param string|null $filename [optional] Path to the filename containing the command history.
 * @return bool TRUE on success or FALSE on failure.
 */
function readline_read_history(?string $filename = null): bool {}

/**
 * Writes the history
 * @param string|null $filename [optional] Path to the saved file.
 * @return bool TRUE on success or FALSE on failure.
 */
function readline_write_history(?string $filename = null): bool {}

/**
 * Registers a completion function
 * @param callable $callback You must supply the name of an existing function which accepts a partial command line and returns an array of possible matches.
 * @return bool TRUE on success or FALSE on failure.
 */
function readline_completion_function(callable $callback): bool {}

/**
 * Initializes the readline callback interface and terminal, prints the prompt and returns immediately
 * @param string $prompt The prompt message.
 * @param callable $callback The callback function takes one parameter; the user input returned.
 * @return bool TRUE on success or FALSE on failure.
 */
function readline_callback_handler_install(string $prompt, callable $callback): bool {}

/**
 * Reads a character and informs the readline callback interface when a line is received
 * @return void No value is returned.
 */
function readline_callback_read_char(): void {}

/**
 * Removes a previously installed callback handler and restores terminal settings
 * @return bool TRUE if a previously installed callback handler was removed, or FALSE if one could not be found.
 */
function readline_callback_handler_remove(): bool {}

/**
 * Redraws the display
 * @return void No value is returned.
 */
function readline_redisplay(): void {}

/**
 * Inform readline that the cursor has moved to a new line
 * @return void No value is returned.
 */
function readline_on_new_line(): void {}
