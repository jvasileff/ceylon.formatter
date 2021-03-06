import ceylon.file {
    parsePath,
    File,
    Reader
}
import ceylon.language.meta.model {
    Attribute
}
import ceylon.language.meta.declaration {
    FunctionDeclaration
}
import ceylon.language.meta {
    type
}
import ceylon.collection {
    MutableList,
    LinkedList
}
"Reads a file with formatting options, parsing it using the metamodel.
 
 This function does exactly the same thing as [[ceylon.formatter.options::formattingFile]];
 for information on the file format, see there. The following is a discussion of the differences
 between the two.
 
 `formattingFile` is a generated function that parses the values and assigns them to
 [[ceylon.formatter.options::FormattingOptions]] members directy, while `formattingFile_meta` is
 hand-written and uses the metamodel to obtain the parser function, parse the value, and assign it.
 This means that the former is regenerated every time a formatting option is added and grows quite
 large, while the latter stays the same.
 
 I honestly don't know which one you'd want to use. Performance-wise, there aren't enough options
 yet (at the time of writing, there's exactly *one*) to determine any difference reliably.
 (If at the time you're reading this, there already are a lot more options, remind me to update
 this documentation.)"
deprecated
FormattingOptions formattingFile_meta(
    "The file to read"
    String filename,
    "The options that will be used if the file and its included files
     don't specify an option"
    FormattingOptions baseOptions = FormattingOptions()) {
    
    return combinedOptions(baseOptions, variableFormattingFile_meta(filename, baseOptions));
}

"An internal version of [[formattingFile]] that specifies a return type of [[VariableOptions]],
 which is needed for the internally performed recursion."
VariableOptions variableFormattingFile_meta(String filename, SparseFormattingOptions baseOptions) {
    
    if (is File file = parsePath(filename).resource) {
        // read the file
        Reader reader = file.Reader();
        MutableList<String> seq = LinkedList<String>();
        while (exists line = reader.readLine()) {
            seq.add(line);
        }
        String[] lines = seq.sequence();
        
        // read included files
        variable VariableOptions options = VariableOptions(baseOptions);
        for (String line in lines) {
            if (line.startsWith("include=")) {
                options = variableFormattingFile_meta(line.terminal(line.size - "include=".size), options);
            }
        }
        
        // read other options
        for (String line in lines) {
            if (!line.startsWith("#") && !line.startsWith("include=")) {
                Integer? indexOfEquals = line.firstIndexWhere('='.equals);
                "Line does not contain an equality sign"
                assert (exists indexOfEquals);
                String optionName = line[...indexOfEquals];
                String optionValue = line[indexOfEquals+1 ...];
                
                Attribute<VariableOptions>? attribute = `VariableOptions`.getAttribute<VariableOptions>(optionName);
                assert (exists attribute);
                
                String fullTypeString = attribute.type.string;
                Integer? endOfPackageIndex = fullTypeString.inclusions("::").first;
                assert (exists endOfPackageIndex);
                String trimmedTypeString = fullTypeString[endOfPackageIndex+2 ...].trim('?'.equals);
                String parseFunctionName = "parse" + trimmedTypeString;
                FunctionDeclaration? parseFunction =
                        `package ceylon.language`.getFunction(parseFunctionName)
                        else `package ceylon.formatter.options`.getFunction(parseFunctionName);
                "Internal error - type not parsable"
                assert (exists parseFunction);
                
                Anything parsedOptionValue = (parseFunction.apply<Anything,[String]>())(optionValue);
                "Internal error - parser function of wrong type"
                assert (type(parsedOptionValue).subtypeOf(attribute.type));
                
                attribute(options).setIfAssignable(parsedOptionValue);
            }
        }
        
        return options;
    } else {
        throw Exception("File '``filename``' not found!");
    }
}
