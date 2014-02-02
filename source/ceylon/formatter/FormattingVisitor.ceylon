import com.redhat.ceylon.compiler.typechecker.tree { Tree { ... }, Node, VisitorAdaptor, NaturalVisitor }
import org.antlr.runtime { TokenStream { la=\iLA }, Token }
import java.lang { Error, Exception }
import ceylon.file { Writer }
import ceylon.interop.java { CeylonIterable }
import ceylon.formatter.options { FormattingOptions }

"A [[com.redhat.ceylon.compiler.typechecker.tree::Visitor]] that writes a formatted version of the
 element (typically a [[com.redhat.ceylon.compiler.typechecker.tree::Tree.CompilationUnit]]) to a
 [[java.io::Writer]]."
shared class FormattingVisitor(
    "The [[TokenStream]] from which the element was parsed;
     this is mainly needed to preserve comments, as they're not present in the AST."
    TokenStream? tokens,
    "The writer to which the subject is written."
    Writer writer,
    "The options for the formatter that control the format of the written code."
    FormattingOptions options) extends VisitorAdaptor() satisfies NaturalVisitor {
    
    FormattingWriter fWriter = FormattingWriter(tokens, writer, options);
    
    // initialize TokenStream
    if (exists tokens) { tokens.la(1); }
    
    shared actual void handleException(Exception? e, Node that) {
        // set breakpoint here
        if (exists e) {
            e.printStackTrace();
        }
    }
    
    shared actual void visitAnnotation(Annotation that) {
        that.visitChildren(this);
        if (is {String*} inlineAnnotations = options.inlineAnnotations) {
            if (exists primary = that.primary,
                exists child = primary.children.get(0),
                exists mainToken = child.mainToken,
                exists text = mainToken.text,
                text in inlineAnnotations) {
                // no line break for these annotations
            } else {
                fWriter.nextLine();
            }
        } else {
            // no line breaks for any annotations
        }
    }
    
    shared actual void visitAnyMethod(AnyMethod that) {
        // override the default Walker's order
        that.annotationList.visit(this);
        that.type.visit(this);
        that.identifier.visit(this);
        if (exists TypeParameterList typeParams = that.typeParameterList) {
            typeParams.visit(this);
        }
        for (ParameterList list in CeylonIterable(that.parameterLists)) {
            list.visit(this);
        }
    }
    
    shared actual void visitAttributeDeclaration(AttributeDeclaration that) {
        value context = fWriter.openContext();
        visitAnyAttribute(that);
        if (exists expression = that.specifierOrInitializerExpression) {
            expression.visit(this);
        }
        if (exists endToken = that.mainEndToken) {
            writeSemicolon(fWriter, that.mainEndToken, context);
        } else {
            fWriter.closeContext(context);
        }
    }
    
    shared actual void visitBlock(Block that) {
        value context = fWriter.writeToken {
            that.mainToken; // "{"
            beforeToken = noLineBreak;
            afterToken = Indent(1);
            spaceBefore = 10;
            spaceAfter = false;
        };
        fWriter.nextLine();
        for (Statement statement in CeylonIterable(that.statements)) {
            statement.visit(this);
            fWriter.nextLine();
        }
        fWriter.writeToken {
            that.mainEndToken; // "}"
            beforeToken = noLineBreak;
            afterToken = noLineBreak;
            spaceBefore = false;
            spaceAfter = 5;
            context;
        };
        fWriter.nextLine();
    }
    
    shared actual void visitIdentifier(Identifier that) {
        fWriter.writeToken {
            that.mainToken;
        };
    }
    
    shared actual void visitInvocationExpression(InvocationExpression that) {
        that.primary.visit(this);
        if (exists PositionalArgumentList list = that.positionalArgumentList) {
            list.visit(this);
        } else if (exists NamedArgumentList list = that.namedArgumentList) {
            list.visit(this);
        }
    }
    
    shared actual void visitLiteral(Literal that) {
        fWriter.writeToken {
            that.mainToken;
            beforeToken = noLineBreak;
            afterToken = noLineBreak;
            spaceBefore = 1;
            spaceAfter = 1;
        };
        if (exists Token endToken = that.mainEndToken) {
            throw Error("Literal has end token ('``endToken``')! Investigate"); // breakpoint here
        }
    }
    
    shared actual void visitMemberOp(MemberOp that) {
        fWriter.writeToken {
            that.mainToken; // "."
            beforeToken = Indent(1);
            afterToken = noLineBreak;
            spaceBefore = false;
            spaceAfter = false;
        };
    }
    
    shared actual void visitMethodDeclaration(MethodDeclaration that) {
        visitAnyMethod(that);
        if (exists SpecifierExpression expr = that.specifierExpression) {
            expr.visit(this);
        }
    }
    
    shared actual void visitMethodDefinition(MethodDefinition that) {
        value context = fWriter.openContext();
        visitAnyMethod(that);
        fWriter.closeContext(context);
        if (options.braceOnOwnLine) {
            fWriter.nextLine();
        }
        that.block.visit(this);
        fWriter.nextLine(); // blank line between method definitions
    }
    
    shared actual void visitParameterList(ParameterList that) {
        value context = fWriter.writeToken {
            that.mainToken; // "("
            afterToken = Indent(1);
            spaceBefore = options.spaceAfterParamListOpeningParen;
            spaceAfter = options.spaceAfterParamListOpeningParen;
        };
        variable FormattingWriter.FormattingContext? previousContext = null;
        for (Parameter parameter in CeylonIterable(that.parameters)) {
            if (exists c = previousContext) {
                fWriter.writeToken {
                    ",";
                    beforeToken = noLineBreak;
                    spaceBefore = false;
                    spaceAfter = true;
                    context = c;
                };
            }
            previousContext = fWriter.openContext();
            parameter.visit(this);
        }
        fWriter.writeToken {
            that.mainEndToken; // ")"
            beforeToken = noLineBreak;
            afterToken = noLineBreak;
            spaceBefore = options.spaceBeforeParamListClosingParen;
            spaceAfter = options.spaceAfterParamListClosingParen;
            context;
        };
    }
    
    shared actual void visitPositionalArgumentList(PositionalArgumentList that) {
        Token? openingParen = that.mainToken;
        Token? closingParen = that.mainEndToken;
        if(exists openingParen, exists closingParen) {
            value context = fWriter.writeToken {
                that.mainToken; // "("
                beforeToken = noLineBreak;
                afterToken = Indent(1);
                spaceBefore = false;
                spaceAfter = false;
            };
            variable FormattingWriter.FormattingContext? previousContext = null;
            for (PositionalArgument argument in CeylonIterable(that.positionalArguments)) {
                if (exists c = previousContext) {
                    fWriter.writeToken {
                        ",";
                        beforeToken = noLineBreak;
                        spaceBefore = false;
                        spaceAfter = true;
                        context = c;
                    };
                }
                previousContext = fWriter.openContext();
                argument.visit(this);
            }
            fWriter.writeToken {
                that.mainEndToken; // ")"
                beforeToken = noLineBreak;
                afterToken = noLineBreak;
                spaceBefore = false;
                spaceAfter = 5;
                context;
            };
        } else {
            // this happens for annotations with no arguments
            assert (that.positionalArguments.empty);
            return;
        }
    }
    
    shared actual void visitQualifiedMemberExpression(QualifiedMemberExpression that) {
        that.primary.visit(this);
        that.memberOperator.visit(this);
        that.identifier.visit(this);
    }
    
    shared actual void visitReturn(Return that) {
        value context = fWriter.writeToken {
            that.mainToken; // "return"
            beforeToken = noLineBreak;
            afterToken = Indent(1);
            spaceAfter = true;
        };
        assert (exists context);
        that.expression.visit(this);
        writeSemicolon(fWriter, that.mainEndToken, context);
    }
    
    shared actual void visitSpecifierExpression(SpecifierExpression that) {
        if (exists mainToken = that.mainToken) {
            writeEquals(fWriter, that.mainToken);
        }
        that.expression.visit(this);
    }
    
    shared actual void visitSpecifierStatement(SpecifierStatement that) {
        value context = fWriter.openContext();
        that.baseMemberExpression.visit(this);
        writeEquals(fWriter, "="); // I can’t find the "=" in the AST anywhere
        that.specifierExpression.visit(this);
        writeSemicolon(fWriter, that.mainEndToken, context);
    }
    
    shared actual void visitStatement(Statement that) {
        value context = fWriter.openContext();
        that.visitChildren(this);
        writeSemicolon(fWriter, that.mainEndToken, context);
    }
    
    shared actual void visitTypedDeclaration(TypedDeclaration that) {
        that.annotationList.visit(this);
        that.type.visit(this);
        that.identifier.visit(this);
    }
    
    shared actual void visitValueModifier(ValueModifier that) {
        writeModifier(fWriter, that.mainToken);
    }
    
    shared actual void visitVoidModifier(VoidModifier that) {
        writeModifier(fWriter, that.mainToken);
    }
    
    //TODO eventually, this will be unneeded, as each visitSomeSubclassOfNode should be overwritten here.
    shared actual void visitAny(Node that) {
        if (exists Token start = that.mainToken) {
            process.writeError(start.text);
            if (exists Token end = that.mainEndToken) {
                process.writeError("\t``end.text``");
            }
            process.writeErrorLine();
        }
        super.visitAny(that); // continue walking the tree
    }
    
    shared void close() {
        fWriter.close();
        writer.close(null);
    }
}