import ceylon.collection {
    MutableMap,
    HashMap,
    MutableList,
    LinkedList
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
    // first of all, the special cases --help and --version, which both cause exiting
    if (arguments.contains("--help")) {
        print(
            "ceylon.formatter – a Ceylon module / program to format Ceylon source code.
             
             USAGE
             
                 ceylon run ceylon.formatter source
             
             or, if you’re worried about it breaking your source code (which shouldn’t happen –
             if anything bad happens, error recovery kicks in and the original file is destroyed)
             or you just want to test it out:
             
                 ceylon run ceylon.formatter source --to source-formatted
             
             You can also format multiple folders at the same time:
             
                 ceylon run ceylon.formatter source --and test-source --to formatted
             
             which will recreate the ‘source’ and ‘test-source’ folders inside the new ‘formatted’ folder.
             
             OPTIONS
             
             --help
                 Print this help message.
             
             --version
                 Print version information. The first line is always just the module name and version
                 in the format that ‘ceylon run’ understands (“ceylon.formatter/x.y.z”), which might be
                 useful for scripts.
             
             --${option name}=${option value}
                 Set a formatting option. See the documentation of the FormattingOptions class for a list of
                 options. The most useful ones are:
                 
                 --maxLineLength
                     The maximum line length, or “unlimited”.
                 
                 --indentMode
                     The indentation mode. Syntax: “x spaces” or “y-wide tabs” or “mix x-wide tabs, y spaces”.
                 
                 --lineBreak
                     “lf”, “crlf”, or “os” for the operating system’s native line breaks."
        );
        process.exit(0);
    } else if (arguments.contains("--version")) {
        print(
            "`` `module ceylon.formatter`.name ``/`` `module ceylon.formatter`.version ``
             Copyright 2014 Lucas Werkmeister
             Licensed under the Apache License, Version 2.0."
        );
        process.exit(0);
    }
    
    variable FormattingOptions baseOptions = configOptions();
    
    String[] splitArguments = concatenate(*arguments.map((String s) {
                if (exists index = s.firstIndexWhere('='.equals)) {
                    return [s[... index - 1], s[index + 1 ...]];
                }
                return [s];
            }));
    value options = VariableOptions(baseOptions);
    value remaining = LinkedList<String>();
    
    if (nonempty splitArguments) {
        variable Integer i = 0;
        while (i < splitArguments.size) {
            assert (exists option = splitArguments[i]);
            String optionName = (sugarOptions[option] else option)["--".size...];
            if (option == "--") {
                remaining.addAll(splitArguments[(i + 1)...]);
                break;
            } else if (optionName.startsWith("no-")) {
                try {
                    parseFormattingOption(optionName["no-".size...], "false", options);
                } catch (ParseOptionException e) {
                    process.writeErrorLine("Option '``optionName["no-".size...]``' is not a boolean option and can’t be used as '``option``'!");
                } catch (UnknownOptionException e) {
                    remaining.add(option);
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
                    remaining.add(option);
                }
            } else {
                try {
                    // maybe it’s a boolean option…
                    parseFormattingOption(optionName, "true", options);
                } catch (ParseOptionException e) {
                    // …nope.
                    process.writeErrorLine("Missing value for option '``optionName``'!");
                } catch (UnknownOptionException e) {
                    remaining.add(option);
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
        MutableMap<String,MutableList<String>> lines = HashMap<String,MutableList<String>>();
        while (exists line = reader.readLine()) {
            if (line.startsWith("#")) {
                continue;
            }
            if (exists i = line.firstIndexWhere('='.equals)) {
                String key = line[... i - 1];
                String item = line[i + 1 ...];
                if (exists appender = lines[key]) {
                    appender.add(item);
                } else {
                    lines.put(key, LinkedList { item });
                }
            } else {
                // TODO report the error somewhere?
                process.writeError("Missing value for option '``line``'!");
            }
        }
        return parseFormattingOptions(lines.map((String->MutableList<String> option) => option.key->option.item.sequence), baseOptions);
    } else {
        throw Exception("File '``filename``' not found!");
    }
}

VariableOptions parseFormattingOptions({<String->{String*}>*} entries, FormattingOptions baseOptions = FormattingOptions()) {
    // read included files
    variable VariableOptions options = VariableOptions(baseOptions);
    if (exists includes = entries.find((String->{String*} entry) => entry.key == "include")?.item) {
        for (include in includes) {
            options = variableFormattingFile(include, options);
        }
    }
    
    // read other options
    for (String->{String*} entry in entries.filter((String->{String*} entry) => entry.key != "include")) {
        String optionName = entry.key;
        assert (exists optionValue = entry.item.last);
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
