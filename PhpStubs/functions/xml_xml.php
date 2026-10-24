<?php

/**
 * Create an XML parser
 * @param string|null $encoding [optional] The optional encoding specifies the character encoding for the input/output in PHP 4. Starting from PHP 5, the input encoding is automatically detected, so that the encoding parameter specifies only the output encoding. In PHP 4, the default output encoding ...
 * @return resource|false|XMLParser a resource handle for the new XML parser.
 */
function xml_parser_create(?string $encoding = null): XMLParser {}

/**
 * Create an XML parser with namespace support
 * @param string|null $encoding [optional] The optional encoding specifies the character encoding for the input/output in PHP 4. Starting from PHP 5, the input encoding is automatically detected, so that the encoding parameter specifies only the output encoding. In PHP 4, the default output encoding ...
 * @param string $separator [optional] With a namespace aware parser tag parameters passed to the various handler functions will consist of namespace and tag name separated by the string specified in separator.
 * @return resource|false|XMLParser a resource handle for the new XML parser.
 */
function xml_parser_create_ns(?string $encoding = null, string $separator = ':'): XMLParser {}

/**
 * Use XML Parser within an object
 * @param XMLParser|resource $parser A reference to the XML parser to use inside the object.
 * @param object $object The object where to use the XML parser.
 * @return bool TRUE on success or FALSE on failure.
 */
function xml_set_object(XMLParser $parser, object $object): true {}

/**
 * Set up start and end element handlers
 * @param XMLParser|resource $parser A reference to the XML parser to set up start and end element handler functions.
 * @param callable|string|null $start_handler The function named by start_element_handler must accept three parameters: start_element_handler resourceparser stringname arrayattribs parser The first parameter, parser, is a reference to the XML parser calling the handler.
 * @param callable|string|null $end_handler The function named by end_element_handler must accept two parameters: end_element_handler resourceparser stringname parser The first parameter, parser, is a reference to the XML parser calling the handler.
 * @return bool TRUE on success or FALSE on failure.
 */
function xml_set_element_handler(
    XMLParser $parser,
    callable|string|null $start_handler,
    callable|string|null $end_handler
): true {}

/**
 * Set up character data handler
 * @param XMLParser|resource $parser A reference to the XML parser to set up character data handler function.
 * @param callable|string|null $handler handler is a string containing the name of a function that must exist when xml_parse is called for parser. The function named by handler must accept two parameters: handler resourceparser stringdata parser The first parameter, parser, is a reference to the XML ...
 * @return bool TRUE on success or FALSE on failure.
 */
function xml_set_character_data_handler(
    XMLParser $parser,
    callable|string|null $handler
): true {}

/**
 * Set up processing instruction (PI) handler
 * @param XMLParser|resource $parser A reference to the XML parser to set up processing instruction (PI) handler function.
 * @param callable|string|null $handler handler is a string containing the name of a function that must exist when xml_parse is called for parser. The function named by handler must accept three parameters: handler resourceparser stringtarget stringdata parser The first parameter, parser, is a ...
 * @return bool TRUE on success or FALSE on failure.
 */
function xml_set_processing_instruction_handler(
    XMLParser $parser,
    callable|string|null $handler
): true {}

/**
 * Set up default handler
 * @param XMLParser|resource $parser A reference to the XML parser to set up default handler function.
 * @param callable|string|null $handler handler is a string containing the name of a function that must exist when xml_parse is called for parser. The function named by handler must accept two parameters: handler resourceparser stringdata parser The first parameter, parser, is a reference to the XML ...
 * @return bool TRUE on success or FALSE on failure.
 */
function xml_set_default_handler(
    XMLParser $parser,
    callable|string|null $handler
): true {}

/**
 * Set up unparsed entity declaration handler
 * @param XMLParser|resource $parser A reference to the XML parser to set up unparsed entity declaration handler function.
 * @param callable|string|null $handler handler is a string containing the name of a function that must exist when xml_parse is called for parser. The function named by handler must accept six parameters: handler resourceparser stringentity_name stringbase stringsystem_id stringpublic_id ...
 * @return bool TRUE on success or FALSE on failure.
 */
function xml_set_unparsed_entity_decl_handler(
    XMLParser $parser,
    callable|string|null $handler
): true {}

/**
 * Set up notation declaration handler
 * @param XMLParser|resource $parser A reference to the XML parser to set up notation declaration handler function.
 * @param callable|string|null $handler handler is a string containing the name of a function that must exist when xml_parse is called for parser. The function named by handler must accept five parameters: handler resourceparser stringnotation_name stringbase stringsystem_id stringpublic_id parser The ...
 * @return bool TRUE on success or FALSE on failure.
 */
function xml_set_notation_decl_handler(
    XMLParser $parser,
    callable|string|null $handler
): true {}

/**
 * Set up external entity reference handler
 * @param XMLParser|resource $parser A reference to the XML parser to set up external entity reference handler function.
 * @param callable|string|null $handler handler is a string containing the name of a function that must exist when xml_parse is called for parser. The function named by handler must accept five parameters, and should return an integer value.If the value returned from the handler is FALSE (which it ...
 * @return bool TRUE on success or FALSE on failure.
 */
function xml_set_external_entity_ref_handler(
    XMLParser $parser,
    callable|string|null $handler
): true {}

/**
 * Set up start namespace declaration handler
 * @param XMLParser|resource $parser A reference to the XML parser.
 * @param callable|string|null $handler handler is a string containing the name of a function that must exist when xml_parse is called for parser. The function named by handler must accept three parameters, and should return an integer value. If the value returned from the handler is FALSE (which it ...
 * @return bool TRUE on success or FALSE on failure.
 */
function xml_set_start_namespace_decl_handler(
    XMLParser $parser,
    callable|string|null $handler
): true {}

/**
 * Set up end namespace declaration handler
 * @param XMLParser|resource $parser A reference to the XML parser.
 * @param callable|string|null $handler handler is a string containing the name of a function that must exist when xml_parse is called for parser. The function named by handler must accept two parameters, and should return an integer value. If the value returned from the handler is FALSE (which it ...
 * @return bool TRUE on success or FALSE on failure.
 */
function xml_set_end_namespace_decl_handler(
    XMLParser $parser,
    callable|string|null $handler
): true {}

/**
 * Start parsing an XML document
 * @param XMLParser|resource $parser A reference to the XML parser to use.
 * @param string $data Chunk of data to parse. A document may be parsed piece-wise by calling xml_parse several times with new data, as long as the is_final parameter is set and TRUE when the last data is parsed.
 * @param bool $is_final [optional] If set and TRUE, data is the last piece of data sent in this parse.
 * @return int 1 on success or 0 on failure. For unsuccessful parses, error information can be retrieved with xml_get_error_code, xml_error_string, xml_get_current_line_number, xml_get_current_column_number and xml_get_current_byte_index. Entity errors are reported at the end of the data thus only if ...
 */
function xml_parse(XMLParser $parser, string $data, bool $is_final = false): int {}

/**
 * Parse XML data into an array structure
 * @param XMLParser|resource $parser A reference to the XML parser.
 * @param string $data A string containing the XML data.
 * @param array &$values An array containing the values of the XML data
 * @param array &$index [optional] An array containing pointers to the location of the appropriate values in the $values.
 * @return int xml_parse_into_struct returns 0 for failure and 1 for success. This is not the same as FALSE and TRUE, be careful with operators such as ===.
 */
function xml_parse_into_struct(XMLParser $parser, string $data, &$values, &$index = null): int|false {}

/**
 * Get XML parser error code
 * @param XMLParser|resource $parser A reference to the XML parser to get error code from.
 * @return int|false Returns one of the error codes listed in the error codes section.
 */
function xml_get_error_code(XMLParser $parser): int {}

/**
 * Get XML parser error string
 * @param int $error_code An error code from xml_get_error_code.
 * @return string|null a string with a textual description of the error code, or NULL if no description was found. Prior to PHP 8.0, FALSE was returned instead of NULL.
 */
function xml_error_string(int $error_code): ?string {}

/**
 * Get current line number for an XML parser
 * @param XMLParser|resource $parser A reference to the XML parser to get line number from.
 * @return int|false This function returns FALSE if parser does not refer to a valid parser, or else it returns which line the parser is currently at in its data buffer.
 */
function xml_get_current_line_number(XMLParser $parser): int {}

/**
 * Get current column number for an XML parser
 * @param XMLParser|resource $parser A reference to the XML parser to get column number from.
 * @return int|false This function returns FALSE if parser does not refer to a valid parser, or else it returns which column on the current line (as given by xml_get_current_line_number) the parser is currently at.
 */
function xml_get_current_column_number(XMLParser $parser): int {}

/**
 * Get current byte index for an XML parser
 * @param XMLParser|resource $parser A reference to the XML parser to get byte index from.
 * @return int|false This function returns FALSE if parser does not refer to a valid parser, or else it returns which byte index the parser is currently at in its data buffer (starting at 0).
 */
function xml_get_current_byte_index(XMLParser $parser): int {}

/**
 * Free an XML parser
 * @param XMLParser|resource $parser A reference to the XML parser to free.
 * @return bool This function returns FALSE if parser does not refer to a valid parser, or else it frees the parser and returns TRUE.
 */
function xml_parser_free(XMLParser $parser): bool {}

/**
 * Set options in an XML parser
 * @param XMLParser|resource $parser A reference to the XML parser to set an option in.
 * @param int $option Which option to set. See below. The following options are available: XML parser options Option constant Data type Description XML_OPTION_CASE_FOLDING integer Controls whether case-folding is enabled for this XML parser. Enabled by default. XML_OPTION_SKIP_TAGSTART integer Specify ...
 * @param mixed $value The option's new value.
 * @return bool This function returns FALSE if parser does not refer to a valid parser, or if the option could not be set. Else the option is set and TRUE is returned.
 * @throws \ValueError Throws a ValueError when an invalid value is passed to option. Prior to PHP 8.0.0, passing an invalid value to option generated an E_WARNING and made the function return false.
 */
function xml_parser_set_option(XMLParser $parser, int $option, $value): bool {}

/**
 * Get options from an XML parser
 * @param XMLParser|resource $parser A reference to the XML parser to get an option from.
 * @param int $option Which option to fetch. XML_OPTION_CASE_FOLDING and XML_OPTION_TARGET_ENCODING are available. See xml_parser_set_option for their description.
 * @return string|int|bool This function returns FALSE if parser does not refer to a valid parser or if option isn't valid (generates also a E_WARNING). Else the option's value is returned.
 * @throws \ValueError Throws a ValueError when an invalid value is passed to option. Prior to PHP 8.0.0, passing an invalid value to option generated a E_WARNING as well as making the function return false.
 */
function xml_parser_get_option(XMLParser $parser, int $option): string|int|bool {}
