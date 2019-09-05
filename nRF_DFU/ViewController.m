//
//  ViewController.m
//  nRF_DFU
//
//  Created by 陈双超 on 2019/9/3.
//  Copyright © 2019 陈双超. All rights reserved.
//

#define queueMainStart dispatch_async(dispatch_get_main_queue(), ^{
#define queueEnd  });

#import "ViewController.h"

@import iOSDFULibrary;
#import "CoreBluetooth/CoreBluetooth.h"

@interface ViewController ()<CBCentralManagerDelegate,CBPeripheralDelegate,LoggerDelegate, DFUServiceDelegate, DFUProgressDelegate>{
    BOOL isDeviceConnected;
}
@property (weak, nonatomic) IBOutlet UIProgressView *progress;

@property (strong,nonatomic) CBCentralManager * centalManager;
@property (strong,nonatomic) CBPeripheral *peripheral;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    self.centalManager = [[CBCentralManager alloc] initWithDelegate:self queue:nil];
    
}

- (IBAction)upGradeAction:(id)sender {
    if (isDeviceConnected) {
        NSString *path = [[NSBundle mainBundle] pathForResource:@"nrf52832_sdk_12.2_app" ofType:@"zip"];
        if (path == nil) {
            NSLog(@"没有升级文件");
            return;
        }
        NSURL *url = [NSURL URLWithString:path];
        DFUFirmware *selectedFirmware = [[DFUFirmware alloc] initWithUrlToZipFile:url];
        
        dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
        DFUServiceInitiator *initiator = [[DFUServiceInitiator alloc] initWithQueue:queue delegateQueue:queue progressQueue:queue loggerQueue:queue];
        initiator = [initiator withFirmware:selectedFirmware];
        
        initiator.logger = self;
        initiator.delegate = self;
        initiator.progressDelegate = self;
        // initiator.peripheralSelector = ... // the default selector is used
        __unused DFUServiceController *controller  = [initiator startWithTarget:self.peripheral];
    }else{
        NSLog(@"未连接设备");
    }
}


//根据蓝牙对象和特性发送数据
-(void)sendDatawithperipheral:(CBPeripheral *)peripheral characteristic:(NSString*)characteristicStr data:(NSData*)data {
    NSLog(@"发送data:%@",data);
    for(int i=0;i<peripheral.services.count;i++){
        for (CBCharacteristic *characteristic in [[peripheral.services objectAtIndex:i] characteristics]){
            //找到通信的的特性
            if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:characteristicStr]]){
                NSLog(@"=============写数据成功");
                [peripheral writeValue:data forCharacteristic:characteristic type:CBCharacteristicWriteWithoutResponse];
            }
        }
    }
}

- (void)searchAction {
    NSLog(@"搜索设备");
    NSDictionary * dic = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:NO],CBCentralManagerScanOptionAllowDuplicatesKey, nil];
    [self.centalManager scanForPeripheralsWithServices:nil options:dic];
}



#pragma mark - Navigation

- (void)centralManagerDidUpdateState:(CBCentralManager *)central{
    switch (central.state) {
        case CBCentralManagerStatePoweredOff:
            break;
        case CBCentralManagerStatePoweredOn:
            [self searchAction];
            break;
        default:
            break;
    }
}


- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI
{
    NSLog(@"发现设备:%@",peripheral.name);
    if (![peripheral.name containsString:@"GLAGOM ONE"]) {
        return;
    }
    
    [self.centalManager stopScan];
    if (!isDeviceConnected) {
        NSLog(@"连接");
        isDeviceConnected = YES;
        [self.centalManager connectPeripheral:peripheral options:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:CBConnectPeripheralOptionNotifyOnDisconnectionKey]];
    }
    self.peripheral = peripheral;
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral{
    NSLog(@"连接成功");
    peripheral.delegate = self;
    [peripheral discoverServices:nil];
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error{
    NSLog(@"连接断开");
    isDeviceConnected = NO;
    [self searchAction];
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error{
    NSLog(@"%@读取到值，接收到数据：%@",peripheral.name,characteristic.value);
    NSString *str = [[NSString alloc] initWithData:characteristic.value encoding:NSUTF8StringEncoding];
    NSLog(@"======%@",str);
    
}

//返回的蓝牙特征值通知代理
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error{
    
    for (CBCharacteristic * characteristic in service.characteristics){
        NSLog(@"%@获取到设备特性:%@",[service.UUID UUIDString],[characteristic.UUID UUIDString]);
//        [peripheral setNotifyValue:YES forCharacteristic:characteristic];
    }
}


- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error{
    for (CBService* service in peripheral.services){
        [peripheral discoverCharacteristics:nil forService:service];
        [peripheral discoverIncludedServices:nil forService:service];
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverDescriptorsForCharacteristic:(nonnull CBCharacteristic *)characteristic error:(nullable NSError *)error{
    
}

#pragma mark - LoggerDelegate
-(void)logWith:(enum LogLevel)level message:(NSString *)message
{
    NSLog(@"%logWith ld: %@", (long) level, message);
}

#pragma mark - DFUServiceDelegate
//更新进度状态  升级开始..升级中断..升级完成等状态
- (void)dfuStateDidChangeTo:(enum DFUState)state{
    
    NSLog(@"DFUState state%ld",state);
    //升级完成
    if (state==DFUStateCompleted) {
        NSLog(@"升级完成");
    }
    
}

//升级error信息
- (void)dfuError:(enum DFUError)error didOccurWithMessage:(NSString * _Nonnull)message{
    
    NSLog(@"Error %ld: %@", (long) error, message);
}

#pragma mark - DFUProgressDelegate
//更新进度
- (void)dfuProgressDidChangeFor:(NSInteger)part outOf:(NSInteger)totalParts to:(NSInteger)progress currentSpeedBytesPerSecond:(double)currentSpeedBytesPerSecond avgSpeedBytesPerSecond:(double)avgSpeedBytesPerSecond{
    queueMainStart
    self->_progress.progress = ((float) progress /totalParts)/100;
    queueEnd
}
@end
