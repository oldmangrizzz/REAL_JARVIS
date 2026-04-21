import Foundation
import PythonKit

// Assuming `GridState` is defined elsewhere and provides a `toPython()` method
// that converts the Swift representation into a Python‑compatible object.
public class PythonRLMBridge {
    private let bridge: PythonObject

    public init() {
        // Import the Python module that implements the RLM bridge.
        self.bridge = Python.import("rlm_bridge")
    }

    /// Resets the environment and returns the initial observation.
    public func reset() -> PythonObject {
        return bridge.reset()
    }

    /// Takes a step in the environment with the given action.
    public func step(action: PythonObject) -> PythonObject {
        return bridge.step(action)
    }

    /// Proposes a new grid configuration given the current state and budgeting constraints.
    ///
    /// - Parameters:
    ///   - gridState: The current grid state representation.
    ///   - timestep: The current timestep in the simulation.
    ///   - budgetTokens: The token budget allocated for the proposal.
    ///   - budgetTime: The time budget (in seconds) allocated for the proposal.
    /// - Returns: A Python object representing the proposal returned by the Python bridge.
    public func propose(gridState: GridState,
                        timestep: Int,
                        budgetTokens: Int,
                        budgetTime: Double) -> PythonObject {
        // Convert the Swift `GridState` to a Python‑compatible representation.
        let pyGridState = gridState.toPython()
        // Forward the call to the Python bridge's `propose_grid` function.
        let result = bridge.propose_grid(pyGridState,
                                         PythonObject(timestep),
                                         PythonObject(budgetTokens),
                                         PythonObject(budgetTime))
        return result
    }
}