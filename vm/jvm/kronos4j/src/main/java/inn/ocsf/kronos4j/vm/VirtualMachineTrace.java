package inn.ocsf.kronos4j.vm;

import org.apache.commons.collections4.map.ListOrderedMap;
import org.apache.commons.lang3.NotImplementedException;

import java.util.Map;

public class VirtualMachineTrace {

    private Map<Long, VirtualMachineTraceStep> steps = new ListOrderedMap<>();

    public Map<Long, VirtualMachineTraceStep> getSteps() {
        return steps;
    }

    public void addStep(Map<String, String> stepParams) {
        long stepIdx = Long.parseLong(stepParams.get("Step"));
        VirtualMachineTraceStep step = new VirtualMachineTraceStep();
        step.stepIdx = stepIdx;
        step.ir = Integer.parseInt(stepParams.get("IR"), 16);
        step.pc = Integer.parseInt(stepParams.get("PC"), 16);
        steps.put(stepIdx, step);
    }

    public static class VirtualMachineTraceStep {
        private long stepIdx;
        private int pc;
        private int ir;

        public long getStepIdx() {
            return stepIdx;
        }

        public int getPc() {
            return pc;
        }

        public int getIr() {
            return ir;
        }
    }
}
