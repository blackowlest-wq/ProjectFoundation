import edu.mit.csail.sdg.alloy4.A4Reporter;
import edu.mit.csail.sdg.alloy4.ErrorWarning;
import edu.mit.csail.sdg.alloy4compiler.ast.Command;
import edu.mit.csail.sdg.alloy4compiler.parser.CompUtil;
import edu.mit.csail.sdg.alloy4compiler.parser.CompModule;
import edu.mit.csail.sdg.alloy4compiler.translator.A4Options;
import edu.mit.csail.sdg.alloy4compiler.translator.A4Solution;
import edu.mit.csail.sdg.alloy4compiler.translator.TranslateAlloyToKodkod;

import java.io.File;

/** Minimal CLI runner for the bounded Alloy 4 models in this directory. */
public final class AlloyRunner {
    private AlloyRunner() {}

    public static void main(String[] args) throws Exception {
        if (args.length != 1) {
            throw new IllegalArgumentException("usage: AlloyRunner <model.als>");
        }
        String filename = new File(args[0]).getCanonicalPath();
        A4Reporter reporter = new A4Reporter() {
            @Override
            public void warning(ErrorWarning warning) {
                System.out.println("WARNING " + warning);
            }
        };
        CompModule world = CompUtil.parseEverything_fromFile(reporter, null, filename);
        A4Options options = new A4Options();
        options.solver = A4Options.SatSolver.SAT4J;
        for (Command command : world.getAllCommands()) {
            System.out.println("COMMAND " + command.label);
            A4Solution solution = TranslateAlloyToKodkod.execute_command(
                    reporter, world.getAllReachableSigs(), command, options);
            if (solution.satisfiable()) {
                System.out.println("COUNTEREXAMPLE " + command.label);
                System.out.println(solution);
            } else {
                System.out.println("PASS " + command.label + ": no instance");
            }
        }
    }
}
