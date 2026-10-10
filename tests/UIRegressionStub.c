// The SwiftUI fixture has no legacy Swift scanner to invoke.
void NWInvokeRefresh(void *adapter, const void *entry) { (void)adapter; (void)entry; }
static int bootstrapCalls;
void NWBootstrapInitialize(void) { ++bootstrapCalls; }
int NWEmbeddedStartupUIRegression(void) { return bootstrapCalls == 1 ? 0 : 1; }
