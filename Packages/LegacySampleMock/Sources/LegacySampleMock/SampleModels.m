#import "SampleModels.h"

static void RequireMainQueue(void) { NSCAssert(NSThread.isMainThread, @"Sample models require the main queue"); }

@interface SampleItemModel ()
@property (nonatomic, readwrite) NSUUID *identifier;
@property (nonatomic, readwrite, copy) NSString *sampleName;
@property (nonatomic, readwrite, copy) NSString *metricValue;
@property (nonatomic, readwrite, copy) NSString *runtime;
@property (nonatomic, readwrite, copy) NSString *iterations;
@property (nonatomic, readwrite, copy) NSString *variant;
@property (nonatomic, readwrite) BOOL isLoading;
@property (nonatomic, readwrite, copy) NSDate *lastMetricTime;
@property (nonatomic, readwrite) NSUInteger serverRevision;
@property (nonatomic, readwrite, copy) NSDecimalNumber *estimatedWork;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *validationTags;
@property (nonatomic, readwrite, copy) NSDictionary<NSString *, NSString *> *rawAttributes;
// Mock-only validation text; the public item API exposes only the error flag.
@property (nonatomic, readonly, copy) NSString *validationError;
// The owning complex sample broadcasts only after all item fields have been updated.
- (void)applyChanges:(NSDictionary<NSString *, NSString *> *)changes;
// Entry readiness changes independently of whole-sample readiness.
- (void)finishLoading;
- (void)tick;
@end

@implementation SampleItemModel
- (instancetype)init {
    if ((self = [super init])) {
        _identifier = NSUUID.UUID;
        _sampleName = @"ArrayMap";
        _metricValue = @"42.00";
        _runtime = @"JAVA";
        _iterations = @"1,234,567";
        _variant = @"BRIDGE V1";
        _sourceModule = @"MOCK-MODULE";
        _bridgeDestination = @"DIRECT";
        _requestID = _identifier.UUIDString;
        _bridgeRequestID = [@"BRIDGE-" stringByAppendingString:_identifier.UUIDString];
        _executionPolicy = @"LAZY";
        _lastMetricTime = NSDate.date;
        _serverRevision = 0;
        _estimatedWork = [NSDecimalNumber decimalNumberWithString:@"0.10"];
        _validationTags = @[@"MOCK", @"BRIDGE_CHECKED"];
        _rawAttributes = @{@"transport": @"legacy-listener", @"revision": @"0"};
    }
    return self;
}
- (BOOL)error { return self.validationError.length > 0; }
- (NSString *)validationError {
    RequireMainQueue();
    if ([self.sampleName stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0) {
        return @"Enter a sample name.";
    }
    NSDecimalNumber *metricValue = [NSDecimalNumber decimalNumberWithString:self.metricValue locale:@{NSLocaleDecimalSeparator: @"."}];
    if ([metricValue isEqual:NSDecimalNumber.notANumber] || [metricValue compare:NSDecimalNumber.zero] != NSOrderedDescending) {
        return @"Metric must be a positive number.";
    }
    return @"";
}
- (void)applyChanges:(NSDictionary<NSString *,NSString *> *)changes {
    RequireMainQueue();
    if (changes[@"sampleName"]) self.sampleName = changes[@"sampleName"];
    if (changes[@"metricValue"]) self.metricValue = changes[@"metricValue"];
    if (changes[@"runtime"]) self.runtime = changes[@"runtime"];
    if (changes[@"iterations"]) self.iterations = changes[@"iterations"];
    if (changes[@"variant"]) self.variant = changes[@"variant"];
}
// Entry readiness changes independently of whole-sample readiness.
- (void)finishLoading {
    RequireMainQueue();
    self.isLoading = NO;
}
- (void)simulateLegacyTick {
    RequireMainQueue();
    self.serverRevision += 1;
    self.lastMetricTime = NSDate.date;
    self.estimatedWork = [self.estimatedWork decimalNumberByAdding:[NSDecimalNumber decimalNumberWithString:@"0.01"]];
    self.validationTags = @[@"MOCK", self.serverRevision % 2 == 0 ? @"CHECKED" : @"RECHECKED"];
    self.rawAttributes = @{@"transport": @"legacy-listener", @"revision": @(self.serverRevision).stringValue};
}
- (void)tick {
    RequireMainQueue();
    if (self.isLoading) return;
    NSDecimalNumber *metricValue = [NSDecimalNumber decimalNumberWithString:self.metricValue locale:@{NSLocaleDecimalSeparator: @"."}];
    if ([metricValue isEqual:NSDecimalNumber.notANumber] || [metricValue compare:NSDecimalNumber.zero] != NSOrderedDescending) return;
    // A non-zero, deterministic mock tick makes stream behavior reproducible.
    NSDecimalNumber *next = [metricValue decimalNumberByAdding:[NSDecimalNumber decimalNumberWithString:@"0.25"]];
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.usesGroupingSeparator = NO;
    formatter.minimumFractionDigits = 2;
    formatter.maximumFractionDigits = 2;
    self.metricValue = [formatter stringFromNumber:next];
}
@end

@interface CompositeSampleModel ()
@property (nonatomic, readwrite) BOOL isUpToDate;
@property (nonatomic, readwrite) BOOL isActive;
@property (nonatomic, readwrite, copy) NSString *validationError;
@property (nonatomic, readwrite, copy) NSArray<SampleItemModel *> *items;
@property (nonatomic, readwrite, copy) NSString *layoutTag;
@property (nonatomic, readwrite) NSUInteger auditSequence;
@property (nonatomic, readwrite, copy) NSDate *lastHeartbeat;
@property (nonatomic, readwrite, copy) NSDecimalNumber *estimatedOverhead;
@property (nonatomic, readwrite, copy) NSDictionary<NSString *, NSString *> *diagnostics;
@property (nonatomic) NSMutableArray<id<CompositeSampleModelListener>> *listeners;
@property (nonatomic) NSTimeInterval loadDelay;
@property (nonatomic) NSTimeInterval itemDelay;
@property (nonatomic) NSTimeInterval metricInterval;
@property (nonatomic, nullable) NSTimer *metricTimer;
@property (nonatomic) NSUInteger generation;
@property (nonatomic) BOOL observing;
@property (nonatomic) BOOL loaded;
- (void)beginMockUpdates;
- (void)endMockUpdates;
@end

@implementation CompositeSampleModel
- (instancetype)init { return [self initWithLoadDelay:1.5 itemDelay:1.5 metricInterval:3.0]; }
- (instancetype)initWithLoadDelay:(NSTimeInterval)loadDelay itemDelay:(NSTimeInterval)itemDelay metricInterval:(NSTimeInterval)metricInterval {
    if ((self = [super init])) {
        _loadDelay = MAX(0, loadDelay);
        _itemDelay = MAX(0, itemDelay);
        _metricInterval = MAX(0, metricInterval);
        _items = @[];
        _validationError = @"";
        _layoutTag = @"radial";
        _bridgeIdentifier = @"MOCK-BRIDGE";
        _moduleIdentifier = @"MOCK-MODULE";
        _textEncoding = @"UTF-8";
        _bridgeStrategy = @"DIRECT";
        _clientReference = NSUUID.UUID.UUIDString;
        _auditSequence = 0;
        _lastHeartbeat = NSDate.date;
        _estimatedOverhead = [NSDecimalNumber decimalNumberWithString:@"1.00"];
        _diagnostics = @{@"connection": @"mock", @"sequence": @"0"};
        _listeners = NSMutableArray.array;
    }
    return self;
}
- (void)dealloc { [_metricTimer invalidate]; }
- (NSUInteger)listenerCount { RequireMainQueue(); return self.listeners.count; }
- (BOOL)error { RequireMainQueue(); return self.validationError.length > 0; }
- (void)addListener:(id<CompositeSampleModelListener>)listener {
    RequireMainQueue();
    if ([self.listeners indexOfObjectIdenticalTo:listener] != NSNotFound) return;
    [self.listeners addObject:listener];
    if (self.listeners.count == 1) [self beginMockUpdates];
}
- (void)removeListener:(id<CompositeSampleModelListener>)listener {
    RequireMainQueue();
    NSUInteger index = [self.listeners indexOfObjectIdenticalTo:listener];
    if (index == NSNotFound) return;
    [self.listeners removeObjectAtIndex:index];
    if (self.listeners.count == 0) [self endMockUpdates];
}
- (void)notifyChange {
    for (id<CompositeSampleModelListener> listener in [self.listeners copy]) [listener onCompositeSampleModelChange];
}
- (void)beginMockUpdates {
    RequireMainQueue();
    if (self.observing) return;
    self.observing = YES;
    NSUInteger generation = ++self.generation;
    [self simulateActive:YES];
    if (!self.observing || self.generation != generation) return;
    if (self.loaded) {
        [self simulateUpToDate:YES];
        if (!self.observing || self.generation != generation) return;
        for (SampleItemModel *item in self.items) if (item.isLoading) [self scheduleItem:item];
    } else {
        [self simulateUpToDate:NO];
        if (!self.observing || self.generation != generation) return;
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.loadDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            CompositeSampleModel *model = weakSelf;
            if (!model || !model.observing || model.generation != generation) return;
            model.items = @[[[SampleItemModel alloc] init]];
            model.loaded = YES;
            [model notifyChange];
            if (!model.observing || model.generation != generation) return;
            [model simulateUpToDate:YES];
        });
    }
    if (!self.observing || self.generation != generation) return;
    if (self.metricInterval > 0) {
        __weak typeof(self) weakSelf = self;
        self.metricTimer = [NSTimer timerWithTimeInterval:self.metricInterval repeats:YES block:^(NSTimer *timer) {
            [weakSelf simulateLegacyTick];
            [weakSelf simulateMetricTick];
        }];
        [NSRunLoop.mainRunLoop addTimer:self.metricTimer forMode:NSRunLoopCommonModes];
    }
}
- (void)endMockUpdates {
    RequireMainQueue();
    self.observing = NO;
    self.generation += 1;
    [self.metricTimer invalidate];
    self.metricTimer = nil;
    [self simulateActive:NO];
    [self simulateUpToDate:NO];
}
// Delayed loading is guarded by run generation and UUID, so deleted items never reappear.
- (void)scheduleItem:(SampleItemModel *)item {
    NSUInteger generation = self.generation;
    NSUUID *identifier = item.identifier;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.itemDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CompositeSampleModel *model = weakSelf;
        if (!model || !model.observing || model.generation != generation) return;
        // A deleted item must never reappear when its delayed response arrives.
        BOOL changed = NO;
        for (SampleItemModel *current in model.items) {
            if ([current.identifier isEqual:identifier] && current.isLoading) {
                [current finishLoading];
                changed = YES;
            }
        }
        if (changed) [model notifyChange];
    });
}
- (nullable SampleItemModel *)appendCopy {
    RequireMainQueue();
    SampleItemModel *previous = self.items.lastObject;
    if (!self.isActive || !self.isUpToDate || self.items.count >= 8 || !previous || previous.isLoading) return nil;
    SampleItemModel *item = [[SampleItemModel alloc] init];
    item.sampleName = previous.sampleName;
    item.metricValue = previous.metricValue;
    item.iterations = previous.iterations;
    item.variant = previous.variant;
    item.runtime = arc4random_uniform(2) == 0 ? @"JAVA" : @"SWIFT";
    item.isLoading = YES;
    self.items = [self.items arrayByAddingObject:item];
    [self notifyChange];
    [self scheduleItem:item];
    return item;
}
- (BOOL)deleteItem:(NSUUID *)identifier {
    RequireMainQueue();
    if (!self.isActive || !self.isUpToDate || self.items.count <= 1) return NO;
    NSMutableArray *items = self.items.mutableCopy;
    NSUInteger index = [items indexOfObjectPassingTest:^BOOL(SampleItemModel *item, NSUInteger index, BOOL *stop) {
        return [item.identifier isEqual:identifier];
    }];
    if (index == NSNotFound) return NO;
    [items removeObjectAtIndex:index];
    self.items = items;
    [self validate];
    [self notifyChange];
    return YES;
}
- (BOOL)updateItem:(NSUUID *)identifier changes:(NSDictionary<NSString *,NSString *> *)changes {
    RequireMainQueue();
    if (!self.isActive || !self.isUpToDate) return NO;
    for (SampleItemModel *item in self.items) {
        if ([item.identifier isEqual:identifier] && !item.isLoading) {
            if (changes[@"runtime"] && ![@[@"JAVA", @"SWIFT"] containsObject:changes[@"runtime"]]) return NO;
            [item applyChanges:changes];
            [self validate];
            // The whole-sample listener observes item edits without subscribing to each item.
            [self notifyChange];
            return YES;
        }
    }
    return NO;
}
// The SDK owns confirmed sample; UI previews must not mutate this array before commit.
- (BOOL)reorderItems:(NSArray<NSUUID *> *)identifiers {
    RequireMainQueue();
    if (!self.isActive || !self.isUpToDate || identifiers.count != self.items.count) return NO;
    if ([NSSet setWithArray:identifiers].count != identifiers.count) return NO;
    NSMutableDictionary<NSUUID *, SampleItemModel *> *byID = NSMutableDictionary.dictionary;
    for (SampleItemModel *item in self.items) byID[item.identifier] = item;
    NSMutableArray *ordered = NSMutableArray.array;
    for (NSUUID *identifier in identifiers) {
        if (!byID[identifier]) return NO;
        [ordered addObject:byID[identifier]];
    }
    self.items = ordered;
    [self notifyChange];
    return YES;
}
- (void)selectLayoutTag:(NSString *)marker {
    RequireMainQueue();
    if (!self.isActive || !self.isUpToDate || ![@[@"radial", @"sequence", @"staged-radial", @"matrix", @"staged-matrix"] containsObject:marker]) return;
    self.layoutTag = marker;
    for (id<CompositeSampleModelListener> listener in [self.listeners copy]) [listener onCompositeSampleModelLayoutTagChange];
}
// Data validation is exposed as a message; edits remain possible so users can correct it.
- (void)validate {
    NSString *error = @"";
    for (SampleItemModel *item in self.items) {
        if (item.validationError.length > 0) {
            error = item.validationError;
            break;
        }
    }
    if (![error isEqual:self.validationError]) {
        self.validationError = error;
        for (id<CompositeSampleModelListener> listener in [self.listeners copy]) [listener onCompositeSampleModelStateChange];
    }
}
- (void)simulateMetricTick {
    RequireMainQueue();
    if (!self.isActive || !self.isUpToDate) return;
    for (SampleItemModel *item in self.items) [item tick];
    // Publish after the batch, so the agent reads all updated metrics in one coherent snapshot.
    [self notifyChange];
}
- (void)simulateLegacyTick {
    RequireMainQueue();
    if (!self.isActive || !self.isUpToDate) return;
    self.auditSequence += 1;
    self.lastHeartbeat = NSDate.date;
    self.estimatedOverhead = [self.estimatedOverhead decimalNumberByAdding:[NSDecimalNumber decimalNumberWithString:@"0.01"]];
    self.diagnostics = @{@"connection": @"mock", @"sequence": @(self.auditSequence).stringValue};
    for (SampleItemModel *item in self.items) [item simulateLegacyTick];
    for (id<CompositeSampleModelListener> listener in [self.listeners copy]) {
        [listener onCompositeSampleModelChange];
        [listener onCompositeSampleModelStateChange];
    }
}
- (void)simulateActive:(BOOL)active {
    RequireMainQueue();
    self.isActive = active;
    for (id<CompositeSampleModelListener> listener in [self.listeners copy]) {
        [listener onCompositeSampleModelStateChange];
        if (!active) [listener onCompositeSampleModelInactive];
    }
}
- (void)simulateUpToDate:(BOOL)upToDate {
    RequireMainQueue();
    self.isUpToDate = upToDate;
    for (id<CompositeSampleModelListener> listener in [self.listeners copy]) {
        if (upToDate) [listener onCompositeSampleModelUpToDate];
        else [listener onCompositeSampleModelNotUpToDate];
    }
}
@end
