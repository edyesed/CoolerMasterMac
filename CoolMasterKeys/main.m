//
//  main.m
//  CoolMasterKeys
//
//  Created by Ed Anderson on 1911/02/.
//  Copyright © 2019 Ed Anderson. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <IOKit/usb/IOUSBLib.h>
#import <IOKit/hid/IOHIDManager.h>

//#define USE_ASYNC_IO    //Comment this line out if you want to use
                          //synchronous calls for reads and writes
#define kTestMessage        "CoolerMaster Test"
//#define k8051_USBCS         0x7f92
#define kOurVendorID        0x2516 //9494    //Vendor ID for coolermaster
#define kOurProductID           159    //Product ID of device BEFORE it
                                        //is programmed (raw device)
//#define kOurProductIDBulkTest   4098    //Product ID of device AFTER it is
                                        //programmed (bulk test device)
 
//Global variables
static IONotificationPortRef    gNotifyPort;
static io_iterator_t            gRawAddedIter;
static io_iterator_t            gRawRemovedIter;
static io_iterator_t            gBulkTestAddedIter;
static io_iterator_t            gBulkTestRemovedIter;
static char                     gBuffer[64];

IOReturn FindInterfaces(IOUSBDeviceInterface **device)
{
    IOReturn                    kr;
    IOUSBFindInterfaceRequest   request;
    io_iterator_t               iterator;
    io_service_t                usbInterface;
    IOCFPlugInInterface         **plugInInterface = NULL;
    IOUSBInterfaceInterface     **interface = NULL;
    HRESULT                     result;
    SInt32                      score;
    UInt8                       interfaceClass;
    UInt8                       interfaceSubClass;
    UInt8                       interfaceNumEndpoints;
    int                         pipeRef;
 
#ifndef USE_ASYNC_IO
    UInt32                      numBytesRead;
    UInt32                      i;
#else
    CFRunLoopSourceRef          runLoopSource;
#endif
 
    //Placing the constant kIOUSBFindInterfaceDontCare into the following
    //fields of the IOUSBFindInterfaceRequest structure will allow you
    //to find all the interfaces
    request.bInterfaceClass = kIOUSBFindInterfaceDontCare;
    request.bInterfaceSubClass = kIOUSBFindInterfaceDontCare;
    request.bInterfaceProtocol = kIOUSBFindInterfaceDontCare;
    request.bAlternateSetting = kIOUSBFindInterfaceDontCare;
 
    //Get an iterator for the interfaces on the device
    kr = (*device)->CreateInterfaceIterator(device,
                                        &request, &iterator);
    while ((usbInterface = IOIteratorNext(iterator)))
    {
        //Create an intermediate plug-in
        kr = IOCreatePlugInInterfaceForService(usbInterface,
                            kIOUSBInterfaceUserClientTypeID,
                            kIOCFPlugInInterfaceID,
                            &plugInInterface, &score);
        //Release the usbInterface object after getting the plug-in
        kr = IOObjectRelease(usbInterface);
        if ((kr != kIOReturnSuccess) || !plugInInterface)
        {
            printf("Unable to create a plug-in (%08x)\n", kr);
            break;
        }
 
        //Now create the device interface for the interface
        result = (*plugInInterface)->QueryInterface(plugInInterface,
                    CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID),
                    (LPVOID *) &interface);
        //No longer need the intermediate plug-in
        (*plugInInterface)->Release(plugInInterface);
 
        if (result || !interface)
        {
            printf("Couldn’t create a device interface for the interface (%08x)\n", (int) result);
            break;
        }
 
        //Get interface class and subclass
        kr = (*interface)->GetInterfaceClass(interface,
                                                    &interfaceClass);
        kr = (*interface)->GetInterfaceSubClass(interface,
                                                &interfaceSubClass);
 
        printf("Interface class %d, subclass %d\n", interfaceClass,
                                                    interfaceSubClass);
 
        //Now open the interface. This will cause the pipes associated with
        //the endpoints in the interface descriptor to be instantiated
        kr = (*interface)->USBInterfaceOpen(interface);
        if (kr != kIOReturnSuccess)
        {
            printf("Unable to open interface (%08x)\n", kr);
            (void) (*interface)->Release(interface);
            break;
        }
 
        //Get the number of endpoints associated with this interface
        kr = (*interface)->GetNumEndpoints(interface,
                                        &interfaceNumEndpoints);
        if (kr != kIOReturnSuccess)
        {
            printf("Unable to get number of endpoints (%08x)\n", kr);
            (void) (*interface)->USBInterfaceClose(interface);
            (void) (*interface)->Release(interface);
            break;
        }
 
        printf("Interface has %d endpoints\n", interfaceNumEndpoints);
        //Access each pipe in turn, starting with the pipe at index 1
        //The pipe at index 0 is the default control pipe and should be
        //accessed using (*usbDevice)->DeviceRequest() instead
        for (pipeRef = 1; pipeRef <= interfaceNumEndpoints; pipeRef++)
        {
            IOReturn        kr2;
            UInt8           direction;
            UInt8           number;
            UInt8           transferType;
            UInt16          maxPacketSize;
            UInt8           interval;
            char            *message;
 
            kr2 = (*interface)->GetPipeProperties(interface,
                                        pipeRef, &direction,
                                        &number, &transferType,
                                        &maxPacketSize, &interval);
            if (kr2 != kIOReturnSuccess)
                printf("Unable to get properties of pipe %d (%08x)\n",
                                        pipeRef, kr2);
            else
            {
                printf("PipeRef %d: ", pipeRef);
                switch (direction)
                {
                    case kUSBOut:
                        message = "out";
                        break;
                    case kUSBIn:
                        message = "in";
                        break;
                    case kUSBNone:
                        message = "none";
                        break;
                    case kUSBAnyDirn:
                        message = "any";
                        break;
                    default:
                        message = "???";
                }
                printf("direction %s, ", message);
 
                switch (transferType)
                {
                    case kUSBControl:
                        message = "control";
                        break;
                    case kUSBIsoc:
                        message = "isoc";
                        break;
                    case kUSBBulk:
                        message = "bulk";
                        break;
                    case kUSBInterrupt:
                        message = "interrupt";
                        break;
                    case kUSBAnyType:
                        message = "any";
                        break;
                    default:
                        message = "???";
                }
                printf("transfer type %s, maxPacketSize %d\n", message,
                                                    maxPacketSize);
            }
        }
 
#ifndef USE_ASYNC_IO    //Demonstrate synchronous I/O
        kr = (*interface)->WritePipe(interface, 2, kTestMessage,
                                            strlen(kTestMessage));
        if (kr != kIOReturnSuccess)
        {
            printf("Unable to perform bulk write (%08x)\n", kr);
            (void) (*interface)->USBInterfaceClose(interface);
            (void) (*interface)->Release(interface);
            break;
        }
 
        printf("Wrote \"%s\" (%u bytes) to bulk endpoint\n", kTestMessage, (unsigned int) strlen(kTestMessage));
 
        numBytesRead = sizeof(gBuffer) - 1; //leave one byte at the end
                                             //for NULL termination
        kr = (*interface)->ReadPipe(interface, 9, gBuffer,
                                            &numBytesRead);
        if (kr != kIOReturnSuccess)
        {
            printf("Unable to perform bulk read (%08x)\n", kr);
            (void) (*interface)->USBInterfaceClose(interface);
            (void) (*interface)->Release(interface);
            break;
        }
 
        //Because the downloaded firmware echoes the one’s complement of the
        //message, now complement the buffer contents to get the original data
        for (i = 0; i < numBytesRead; i++)
            gBuffer[i] = ~gBuffer[i];
 
        printf("Read \"%s\" (%u bytes) from bulk endpoint\n", gBuffer,
               (unsigned int)numBytesRead);
 
#else   //Demonstrate asynchronous I/O
        //As with service matching notifications, to receive asynchronous
        //I/O completion notifications, you must create an event source and
        //add it to the run loop
        kr = (*interface)->CreateInterfaceAsyncEventSource(
                                    interface, &runLoopSource);
        if (kr != kIOReturnSuccess)
        {
            printf("Unable to create asynchronous event source
                                    (%08x)\n", kr);
            (void) (*interface)->USBInterfaceClose(interface);
            (void) (*interface)->Release(interface);
            break;
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource,
                            kCFRunLoopDefaultMode);
        printf("Asynchronous event source added to run loop\n");
        bzero(gBuffer, sizeof(gBuffer));
        strcpy(gBuffer, kTestMessage);
        kr = (*interface)->WritePipeAsync(interface, 2, gBuffer,
                                    strlen(gBuffer),
                                    WriteCompletion, (void *) interface);
        if (kr != kIOReturnSuccess)
        {
            printf("Unable to perform asynchronous bulk write (%08x)\n",
                                                    kr);
            (void) (*interface)->USBInterfaceClose(interface);
            (void) (*interface)->Release(interface);
            break;
        }
#endif
        //For this test, just use first interface, so exit loop
        break;
    }
    return kr;
}

void BulkTestDeviceAdded(void *refCon, io_iterator_t iterator)
{
    kern_return_t           kr;
    io_service_t            usbDevice;
    IOUSBDeviceInterface    **device=NULL;
 
    while ((usbDevice = IOIteratorNext(iterator)))
    {
        //Create an intermediate plug-in using the
        //IOCreatePlugInInterfaceForService function
 
        //Release the device object after getting the intermediate plug-in
 
        //Create the device interface using the QueryInterface function
 
        //Release the intermediate plug-in object
 
        //Check the vendor, product, and release number values to
        //confirm we’ve got the right device
 
        //Open the device before configuring it
        kr = (*device)->USBDeviceOpen(device);
 
        //Configure the device by calling ConfigureDevice
 
        //Close the device and release the device interface object if
        //the configuration is unsuccessful
 
        //Get the interfaces
        kr = FindInterfaces(device);
        if (kr != kIOReturnSuccess)
        {
            printf("Unable to find interfaces on device: %08x\n", kr);
            (*device)->USBDeviceClose(device);
            (*device)->Release(device);
            continue;
        }
 
//If using synchronous IO, close and release the device interface here
#ifndef USB_ASYNC_IO
        kr = (*device)->USBDeviceClose(device);
        kr = (*device)->Release(device);
#endif
    }
}



void RawDeviceRemoved(void *refCon, io_iterator_t iterator)
{
    kern_return_t   kr;
    io_service_t    object;
 
    while ((object = IOIteratorNext(iterator)))
    {
        kr = IOObjectRelease(object);
        if (kr != kIOReturnSuccess)
        {
            printf("Couldn’t release raw device object: %08x\n", kr);
            continue;
        }
    }
}

//IOReturn WriteToDevice(IOUSBDeviceInterface **dev,
//                        UInt16 length, UInt8 *writeBuffer)
IOReturn WriteToDevice(IOUSBDeviceInterface **dev)
{
    IOUSBDevRequest     request;
    //UInt8           requestData;
 
    UInt8 requestData[64] = { 0x51, 0x28, 0x00, 0x00, 0x04 };
    request.bmRequestType = USBmakebmRequestType(kUSBOut, kUSBVendor,
                                                kUSBDevice);
    request.bRequest = 01; // 51 sets effects https://github.com/chmod222/libcmmk/blob/master/PROTOCOL.md#5x-28-get-or-set-active-effect
    request.wValue = 0x04; // 3 is the writer interface for keyboard
    request.wIndex = 0;
    request.wLength = sizeof(requestData);
    request.pData = &requestData;
 
    return (*dev)->DeviceRequest(dev, &request);
}

// DownloadToDevice seems unnecessary for the keyboard use case.
//
IOReturn PipeToDevice(IOUSBDeviceInterface **dev)
{
    //ok UInt8       writeVal [64];
    IOReturn    kr;

    //Assert reset. This tells the device that the download is
    //about to occur
    //writeVal = 1;   //For this device, a value of 1 indicates a download
    //ok writeVal[0] = 51;
    //ok writeVal[1] = 28;
    //ok writeVal[2] = 0x09;
    //kr = WriteToDevice(dev, 64, &writeVal);
    kr = WriteToDevice(dev);
    if (kr != kIOReturnSuccess)
    {
        printf("WriteToDevice returned err 0x%x\n", kr);
        (*dev)->USBDeviceClose(dev);
        (*dev)->Release(dev);
        return kr;
    }

    //De-assert reset. This tells the device that the download is complete
    //writeVal = 0;
    //kr = WriteToDevice(dev, 1, &writeVal);
    //if (kr != kIOReturnSuccess)
    //    printf("WriteToDevice run returned err 0x%x\n", kr);

    return kr;
}
 
IOReturn ConfigureDevice(IOUSBDeviceInterface **dev)
{
    UInt8                           numConfig;
    IOReturn                        kr;
    IOUSBConfigurationDescriptorPtr configDesc;
 
    //Get the number of configurations. The sample code always chooses
    //the first configuration (at index 0) but your code may need a
    //different one
    kr = (*dev)->GetNumberOfConfigurations(dev, &numConfig);
    if (!numConfig)
        return -1;
 
    UInt8 index = 0x83;
    //Get the configuration descriptor for index 0
    kr = (*dev)->GetConfigurationDescriptorPtr(dev, index, &configDesc);
    if (kr)
    {
        printf("Couldn’t get configuration descriptor for index %d (err=%08x)\n", index, kr);
        return -1;
    }
 
    //Set the device’s configuration. The configuration value is found in
    //the bConfigurationValue field of the configuration descriptor
    kr = (*dev)->SetConfiguration(dev, configDesc->bConfigurationValue);
    if (kr)
    {
        printf("Couldn’t set configuration to value %d (err = %08x)\n", 0,
                kr);
        return -1;
    }
    return kIOReturnSuccess;
}



void RawDeviceAdded(void *refCon, io_iterator_t iterator)
{
    kern_return_t               kr;
    io_service_t                usbDevice;
    IOCFPlugInInterface         **plugInInterface = NULL;
    IOUSBDeviceInterface        **dev = NULL;
    HRESULT                     result;
    SInt32                      score;
    UInt16                      vendor;
    UInt16                      product;
    UInt16                      release;
 
    while ((usbDevice = (IOIteratorNext(iterator))))
    {
        //Create an intermediate plug-in
        kr = IOCreatePlugInInterfaceForService(usbDevice,
                    kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID,
                    &plugInInterface, &score);
        //Don’t need the device object after intermediate plug-in is created
        kr = IOObjectRelease(usbDevice);
        if ((kIOReturnSuccess != kr) || !plugInInterface)
        {
            printf("Unable to create a plug-in (%08x)\n", kr);
            continue;
        }
        //Now create the device interface
        result = (*plugInInterface)->QueryInterface(plugInInterface,
                        CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID),
                        (LPVOID *)&dev);
        //Don’t need the intermediate plug-in after device interface
        //is created
        (*plugInInterface)->Release(plugInInterface);
 
        if (result || !dev)
        {
            printf("Couldn’t create a device interface (%08x)\n",
                                                    (int) result);
            continue;
        }
 
        //Check these values for confirmation
        kr = (*dev)->GetDeviceVendor(dev, &vendor);
        kr = (*dev)->GetDeviceProduct(dev, &product);
        kr = (*dev)->GetDeviceReleaseNumber(dev, &release);
        //if ((vendor != kOurVendorID) || (release != 1))
        if ((vendor != kOurVendorID) || (release != 16))
        {
            printf("Found unwanted device (vendor = %d, product = %d)\n",
                    vendor, product);
            (void) (*dev)->Release(dev);
            continue;
        }
 
        //Open the device to change its state
        kr = (*dev)->USBDeviceOpen(dev);
        if (kr != kIOReturnSuccess)
        {
            printf("Unable to open device: %08x\n", kr);
            (void) (*dev)->Release(dev);
            continue;
        }
        //Configure device
        kr = ConfigureDevice(dev);
        if (kr != kIOReturnSuccess)
        {
            printf("Unable to configure device: %08x\n", kr);
            (void) (*dev)->USBDeviceClose(dev);
            (void) (*dev)->Release(dev);
            continue;
        }
 
// DownloadToDevice seems unnecessary for the keyboard use case
        //pipe some commands firmware to device
        kr = PipeToDevice(dev);
        if (kr != kIOReturnSuccess)
        {
            printf("Unable to pipe commands to device: %08x\n", kr);
            (void) (*dev)->USBDeviceClose(dev);
            (void) (*dev)->Release(dev);
            continue;
        }
        
 
        //Close this device and release object
        kr = (*dev)->USBDeviceClose(dev);
        kr = (*dev)->Release(dev);
    }
}


int main (int argc, const char *argv[])
{
                mach_port_t             masterPort;
                CFMutableDictionaryRef  matchingDict;
                CFRunLoopSourceRef      runLoopSource;
                kern_return_t           kr;
                SInt32                  usbVendor = kOurVendorID;
                SInt32                  usbProduct = kOurProductID;
                
                // Get command line arguments, if any
                if (argc > 1)
                    usbVendor = atoi(argv[1]);
                if (argc > 2)
                    usbProduct = atoi(argv[2]);
                
                //Create a master port for communication with the I/O Kit
                kr = IOMasterPort(MACH_PORT_NULL, &masterPort);
                if (kr || !masterPort)
                {
                    printf("ERR: Couldn’t create a master I/O Kit port(%08x)\n", kr);
                    return -1;
                }
                //Set up matching dictionary for class IOUSBDevice and its subclasses
                matchingDict = IOServiceMatching(kIOUSBDeviceClassName);
                if (!matchingDict)
                {
                    printf("Couldn’t create a USB matching dictionary\n");
                    mach_port_deallocate(mach_task_self(), masterPort);
                    return -1;
                }
                
                //Add the vendor and product IDs to the matching dictionary.
                //This is the second key in the table of device-matching keys of the
                //USB Common Class Specification
                CFDictionarySetValue(matchingDict, CFSTR(kUSBVendorName),
                                     CFNumberCreate(kCFAllocatorDefault,
                                                    kCFNumberSInt32Type, &usbVendor));
                CFDictionarySetValue(matchingDict, CFSTR(kUSBProductName),
                                     CFNumberCreate(kCFAllocatorDefault,
                                                    kCFNumberSInt32Type, &usbProduct));
                
                //To set up asynchronous notifications, create a notification port and
                //add its run loop event source to the program’s run loop
                gNotifyPort = IONotificationPortCreate(masterPort);
                runLoopSource = IONotificationPortGetRunLoopSource(gNotifyPort);
                CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource,
                                   kCFRunLoopDefaultMode);
                
                //Retain additional dictionary references because each call to
                //IOServiceAddMatchingNotification consumes one reference
                matchingDict = (CFMutableDictionaryRef) CFRetain(matchingDict);
                matchingDict = (CFMutableDictionaryRef) CFRetain(matchingDict);
                matchingDict = (CFMutableDictionaryRef) CFRetain(matchingDict);
                
                //Now set up two notifications: one to be called when a raw device
                //is first matched by the I/O Kit and another to be called when the
                //device is terminated
                //Notification of first match:
                kr = IOServiceAddMatchingNotification(gNotifyPort,
                                                      kIOFirstMatchNotification, matchingDict,
                                                      RawDeviceAdded, NULL, &gRawAddedIter);
                //Iterate over set of matching devices to access already-present devices
                //and to arm the notification
                RawDeviceAdded(NULL, gRawAddedIter);
                
                //Notification of termination:
                kr = IOServiceAddMatchingNotification(gNotifyPort,
                                                      kIOTerminatedNotification, matchingDict,
                                                      RawDeviceRemoved, NULL, &gRawRemovedIter);
                //Iterate over set of matching devices to release each one and to
                //arm the notification
                RawDeviceRemoved(NULL, gRawRemovedIter);
                
//                //Now change the USB product ID in the matching dictionary to match
//                //the one the device will have after the firmware has been downloaded
//                usbProduct = kOurProductIDBulkTest;
//                CFDictionarySetValue(matchingDict, CFSTR(kUSBProductName),
//                                     CFNumberCreate(kCFAllocatorDefault,
//                                                    kCFNumberSInt32Type, &usbProduct));
//
//                //Now set up two notifications: one to be called when a bulk test device
//                //is first matched by the I/O Kit and another to be called when the
//                //device is terminated.
//                //Notification of first match
//                kr = IOServiceAddMatchingNotification(gNotifyPort,
//                                                      kIOFirstMatchNotification, matchingDict,
//                                                      BulkTestDeviceAdded, NULL, &gBulkTestAddedIter);
//                //Iterate over set of matching devices to access already-present devices
//                //and to arm the notification
//                BulkTestDeviceAdded(NULL, gBulkTestAddedIter);
//
//                //Notification of termination
//                kr = IOServiceAddMatchingNotification(gNotifyPort,
//                                                      kIOTerminatedNotification, matchingDict,
//                                                      BulkTestDeviceRemoved, NULL, &gBulkTestRemovedIter);
//                //Iterate over set of matching devices to release each one and to
//                //arm the notification. NOTE: this function is not shown in this document.
//                BulkTestDeviceRemoved(NULL, gBulkTestRemovedIter);
//
//                //Finished with master port
//                mach_port_deallocate(mach_task_self(), masterPort);
//                masterPort = 0;
                
                //Start the run loop so notifications will be received
                CFRunLoopRun();
                
                //Because the run loop will run forever until interrupted,
                //the program should never reach this point
                return 0;
            }
                   
                   

