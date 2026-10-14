#ifndef NW_COMPATIBILITY_H
#define NW_COMPATIBILITY_H
// Candidate admission, not device acceptance. XNU slot/PF declarations were
// compared through f6217f891ac0bb64f3d375211650a4c1ff8ca1ea. Every caller must
// still validate its runtime contract before sending commands or changing PF.
static inline int NWTransportOSContract(unsigned ios, unsigned darwin) {
    return (ios >= 15 && ios <= 18 && darwin == ios + 6) ||
           (ios == 26 && darwin == 25);
}
static inline int NWPFKernelContract(unsigned darwin) {
    return darwin >= 21 && darwin <= 25;
}
#endif
