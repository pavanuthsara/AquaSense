package com.aquasense.backend.export.client;

public class ExportSimulatorException extends RuntimeException {
    private final boolean invalidInput;

    public ExportSimulatorException(String message, boolean invalidInput, Throwable cause) {
        super(message, cause);
        this.invalidInput = invalidInput;
    }

    /** True when the simulator rejected the input (HTTP 422), false when it is down or failing. */
    public boolean isInvalidInput() {
        return invalidInput;
    }
}
