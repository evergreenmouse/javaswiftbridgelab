#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Runtime contract: commands, property reads and callbacks use the main queue.
// Swift actor isolation belongs to the Swift adapter, not this Objective-C API.

// Items contain values only; CompositeSampleModel publishes their changes as a whole-sample event.
@interface SampleItemModel : NSObject
@property (nonatomic, readonly) NSUUID *identifier;
@property (nonatomic, readonly, copy) NSString *sampleName;
@property (nonatomic, readonly, copy) NSString *metricValue;
@property (nonatomic, readonly, copy) NSString *runtime;
@property (nonatomic, readonly, copy) NSString *iterations;
@property (nonatomic, readonly, copy) NSString *variant;
@property (nonatomic, readonly) BOOL isLoading;
// The sample collection reports a validation error; this flag identifies affected items.
@property (nonatomic, readonly) BOOL error;

// Legacy-only data. These fields deliberately do not belong to the board's Swift snapshots.
@property (nonatomic, readonly, copy) NSString *sourceModule;
@property (nonatomic, readonly, copy) NSString *bridgeDestination;
@property (nonatomic, readonly, copy) NSString *requestID;
@property (nonatomic, readonly, copy) NSString *bridgeRequestID;
@property (nonatomic, readonly, copy) NSString *executionPolicy;
@property (nonatomic, readonly, copy) NSDate *lastMetricTime;
@property (nonatomic, readonly) NSUInteger serverRevision;
@property (nonatomic, readonly, copy) NSDecimalNumber *estimatedWork;
@property (nonatomic, readonly, copy) NSArray<NSString *> *validationTags;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *rawAttributes;

- (void)simulateLegacyTick;
@end

@protocol CompositeSampleModelListener <NSObject>
// Whole-sample changes include item edits, loading completion and metric batches.
- (void)onCompositeSampleModelChange;
- (void)onCompositeSampleModelUpToDate;
- (void)onCompositeSampleModelInactive;
- (void)onCompositeSampleModelStateChange;
- (void)onCompositeSampleModelNotUpToDate;
- (void)onCompositeSampleModelLayoutTagChange;
@end

@interface CompositeSampleModel : NSObject
@property (nonatomic, readonly) BOOL isUpToDate;
@property (nonatomic, readonly) BOOL isActive;
@property (nonatomic, readonly, copy) NSString *validationError;
@property (nonatomic, readonly) BOOL error;
@property (nonatomic, readonly, copy) NSArray<SampleItemModel *> *items;
@property (nonatomic, readonly, copy) NSString *layoutTag;

// Legacy-only bridge and transport metadata.
@property (nonatomic, readonly, copy) NSString *bridgeIdentifier;
@property (nonatomic, readonly, copy) NSString *moduleIdentifier;
@property (nonatomic, readonly, copy) NSString *textEncoding;
@property (nonatomic, readonly, copy) NSString *bridgeStrategy;
@property (nonatomic, readonly, copy) NSString *clientReference;
@property (nonatomic, readonly) NSUInteger auditSequence;
@property (nonatomic, readonly, copy) NSDate *lastHeartbeat;
@property (nonatomic, readonly, copy) NSDecimalNumber *estimatedOverhead;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *diagnostics;

@property (nonatomic, readonly) NSUInteger listenerCount;
- (instancetype)initWithLoadDelay:(NSTimeInterval)loadDelay
                      itemDelay:(NSTimeInterval)itemDelay
                   metricInterval:(NSTimeInterval)metricInterval NS_DESIGNATED_INITIALIZER;
- (instancetype)init;
// Listeners are retained by an array; duplicate registration and unknown removal are no-ops.
// The mock generates data while at least one listener is registered.
- (void)addListener:(id<CompositeSampleModelListener>)listener NS_SWIFT_NAME(addListener(_:));
- (void)removeListener:(id<CompositeSampleModelListener>)listener NS_SWIFT_NAME(removeListener(_:));
- (nullable SampleItemModel *)appendCopy;
- (BOOL)deleteItem:(NSUUID *)identifier;
- (BOOL)updateItem:(NSUUID *)identifier changes:(NSDictionary<NSString *, NSString *> *)changes;
- (BOOL)reorderItems:(NSArray<NSUUID *> *)identifiers;
- (void)selectLayoutTag:(NSString *)marker;

// Explicit mock events also allow deterministic tests without waiting for a timer.
- (void)simulateMetricTick;
- (void)simulateLegacyTick;
- (void)simulateActive:(BOOL)active;
- (void)simulateUpToDate:(BOOL)upToDate;
@end

NS_ASSUME_NONNULL_END
