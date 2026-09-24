package debug.swift.android

import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect

/** Wrap a host Compose subtree to count successful recompositions. */
@Composable
fun DebugSwiftComposeProbe(content: @Composable () -> Unit) {
    SideEffect { AndroidDebugTools.recordComposeRender() }
    content()
}
