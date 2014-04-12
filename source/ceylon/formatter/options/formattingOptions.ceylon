import ceylon.collection {
    MutableMap,
    HashMap
}
import ceylon.file {
    Reader,
    File,
    parsePath
}
"Reads a file with formatting options.
 
 The file consists of lines of key=value pairs or comments, like this:
 ~~~~plain
 # Boss Man says the One True Style is evil
 blockBraceOnNewLine=true
 # 80 characters is not enough
 maxLineWidth=120
 indentMode=4 spaces
 ~~~~
 As you can see, comment lines begin with a `#` (`\\{0023}`), and the value
 doesn't need to be quoted to contain spaces. Blank lines are also allowed.
 
 The keys are attributes of [[FormattingOptions]].
 The format of the value depends on the type of the key; to parse it, the
 function `parse<KeyType>(String)` is used (e.g [[ceylon.language::parseInteger]]
 for `Integer` values, [[ceylon.language::parseBoolean]] for `Boolean` values, etc.).
 
 A special option in this regard is `include`: It is not an attribute of
 `FormattingOptions`, but instead specifies another file to be loaded.
 
 The file is processed in the following order:
 
 1. First, load [[baseOptions]].
 2. Then, scan the file for any `include` options, and process any included files.
 3. Lastly, parse all other lines.
 
 Thus, options in the top-level file override options in included files.
 
 For another function which does exactly the same thing in a different way,
 see [[formattingFile_meta]]."
shared FormattingOptions formattingFile(
    "The file to read"
    String filename,
    "The options that will be used if the file and its included files
     don't specify an option"
    FormattingOptions baseOptions = FormattingOptions())
        => variableFormattingFile(filename, baseOptions);

Map<String,String> sugarOptions = HashMap { "-w"->"--maxLineLength", "--maxLineWidth"->"--maxLineLength" };
Map<String,Anything(VariableOptions)> presets = HashMap {
    "--allmanStyle"->(void(VariableOptions options) => options.braceOnOwnLine = true)
};

shared [FormattingOptions, String[]] commandLineOptions(String[] arguments = process.arguments) {
    variable FormattingOptions baseOptions = FormattingOptions();
    
    String[] splitArguments = concatenate(*arguments.map((String s) {
                if (exists index = s.indexes('='.equals).first) {
                    return [s[... index - 1], s[index + 1 ...]];
                }
                return [s];
            }));
    value options = VariableOptions(baseOptions);
    value remaining = SequenceBuilder<String>();
    
    if (nonempty splitArguments) {
        variable Integer i = 0;
        while (i < splitArguments.size) {
            assert (exists option = splitArguments[i]);
            String optionName = (sugarOptions[option] else option)["--".size...];
            if (option == "--") {
                remaining.appendAll(splitArguments[(i + 1)...]);
                break;
            } else if (optionName.startsWith("no-")) {
                try {
                    parseFormattingOption(optionName["no-".size...], "false", options);
                } catch (ParseOptionException e) {
                    process.writeErrorLine("Option '``optionName["no-".size...]``' is not a boolean option and can’t be used as '``option``'!");
                } catch (UnknownOptionException e) {
                    remaining.append(option);
                }
            } else if (exists preset = presets[option]) {
                preset(options);
            } else if (exists optionValue = splitArguments[i + 1]) {
                try {
                    parseFormattingOption(optionName, optionValue, options);
                    i++;
                } catch (ParseOptionException e) {
                    // maybe it’s a boolean option
                    try {
                        parseFormattingOption(optionName, "true", options);
                    } catch (ParseOptionException f) {
                        if (optionValue.startsWith("-")) {
                            process.writeErrorLine("Missing value for option '``optionName``'!");
                        } else {
                            process.writeErrorLine(e.message);
                            i++;
                        }
                    }
                } catch (UnknownOptionException e) {
                    remaining.append(option);
                }
            } else {
                try {
                    // maybe it’s a boolean option…
                    parseFormattingOption(optionName, "true", options);
                } catch (ParseOptionException e) {
                    // …nope.
                    process.writeErrorLine("Missing value for option '``optionName``'!");
                } catch (UnknownOptionException e) {
                    remaining.append(option);
                }
            }
            i++;
        }
    }
    return [options, remaining.sequence];
}

"An internal version of [[formattingFile]] that specifies a return type of [[VariableOptions]],
 which is needed for the internally performed recursion."
VariableOptions variableFormattingFile(String filename, FormattingOptions baseOptions) {
    
    if (is File file = parsePath(filename).resource) {
        // read the file
        Reader reader = file.Reader();
        MutableMap<String,SequenceAppender<String>> lines = HashMap<String,SequenceAppender<String>>();
        while (exists line = reader.readLine()) {
            if (line.startsWith("#")) {
                continue;
            }
            if (exists i = line.indexes('='.equals).first) {
                String key = line[... i - 1];
                String item = line[i + 1 ...];
                if (exists appender = lines[key]) {
                    appender.append(item);
                } else {
                    lines.put(key, SequenceAppender([item]));
                }
            } else {
                // TODO report the error somewhere?
                process.writeError("Missing value for option '``line``'!");
            }
        }
        return parseFormattingOptions(lines.map((String->SequenceAppender<String> option) => option.key->option.item.sequence), baseOptions);
    } else {
        throw Exception("File '``filename``' not found!");
    }
}

VariableOptions parseFormattingOptions({<String->{String+}>*} entries, FormattingOptions baseOptions) {
    // read included files
    variable VariableOptions options = VariableOptions(baseOptions);
    if (exists includes = entries.find((String->{String+} entry) => entry.key == "include")?.item) {
        for (include in includes) {
            options = variableFormattingFile(include, options);
        }
    }
    
    // read other options
    for (String->{String+} entry in entries.filter((String->{String+} entry) => entry.key != "include")) {
        String optionName = entry.key;
        String optionValue = entry.item.last;
        try {
            parseFormattingOption(optionName, optionValue, options);
        } catch (Exception e) {
            process.writeErrorLine(e.message);
        }
    }
    
    return options;
}

shared Range<Integer>? parseIntegerRange(String string) {
    value parts = string.split('.'.equals).sequence;
    if (parts.size == 2,
        exists first = parseInteger(parts[0] else "invalid"),
        exists last = parseInteger(parts[1] else "invalid")) {
        return first..last;
    }
    return null;
}
