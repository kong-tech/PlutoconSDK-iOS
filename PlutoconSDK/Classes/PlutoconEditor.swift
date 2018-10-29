//
//  PlutoconEditor.swift
//  PlutoconSDK
//
//  Created by 김동혁 on 2018. 1. 18..
//

import Foundation
import CoreBluetooth

internal protocol PlutoconEditorDelegate {
    func plutoconEditor(writeCharacteristic uuid: CBUUID, data: Data)
    func plutoconEditorGetUuid() -> String
}

public class PlutoconEditor: NSObject {
    public static let TX_POWER_TEMPLATE: [Int] = [-40, -30, -20, -16, -12, -8, -4, 0, 4]
    
    fileprivate var operationList: [(CBUUID, Data)] = []
    
    fileprivate var operationCompletion: OperationCompletion?
    
    fileprivate weak var plutoconConnection: PlutoconConnection?
    fileprivate var delegate: PlutoconEditorDelegate?
    
    internal init(delegate: PlutoconEditorDelegate?, plutoconConnection: PlutoconConnection) {
        self.delegate = delegate
        
        self.plutoconConnection = plutoconConnection
    }
    
    public func setOperationCompletion(completion: @escaping OperationCompletion) -> PlutoconEditor {
        self.operationCompletion = completion
        return self
    }
    
    fileprivate func getUuidFromPlace(baseUuid: String, latitude: Double, isLatitudeNegative: Bool, longitude: Double, isLongitudeNegative: Bool) -> String {
        var uuid: String = baseUuid;
        let slatitude: String = (isLatitudeNegative ? "1" : "0") + String(format: "%03d%06d", Int(latitude), Int(((latitude - Double(Int(latitude))) * 1000000)));
        let slongitude: String = (isLongitudeNegative ? "1" : "0") + String(format: "%03d%06d", Int(longitude), Int(((longitude - Double(Int(longitude))) * 1000000)));
        
        uuid = uuid.subString(start:0, end: 8) + "-" + slatitude.subString(start: 0, end: 4) + "-" + uuid.subString(start: 12, end: uuid.count)
        uuid = uuid.subString(start: 0, end: 14) + slatitude.subString(start: 4, end: 8) + "-" + uuid.subString(start: 18, end: uuid.count)
        uuid = uuid.subString(start: 0, end: 19) + slatitude.subString(start: 8, end: 10) + uuid.subString(start: 21, end: uuid.count)
        
        uuid = uuid.subString(start: 0, end: 21) + slongitude.subString(start: 0, end: 2) + "-" + uuid.subString(start: 23, end: uuid.count)
        uuid = uuid.subString(start: 0, end: 24) + slongitude.subString(start: 2, end: 4) + uuid.subString(start: 26, end: uuid.count)
        uuid = uuid.subString(start: 0, end: 26) + slongitude.subString(start: 4, end: 10) + uuid.subString(start: 36, end: uuid.count)
        
        return uuid;
    }
    
    public func setGeofence(latitude: Double, longitude: Double) -> PlutoconEditor {
        let uuidFromPlace = self.getUuidFromPlace(baseUuid: delegate?.plutoconEditorGetUuid() ?? "", latitude: latitude, isLatitudeNegative: latitude < 0, longitude: longitude, isLongitudeNegative: longitude < 0)
        return setUUID(uuidString: uuidFromPlace)
    }
    
    /**
     * UUID 변경은 00000000-0000-0000-0000-000000000000 포맷과 일치해야 값을 변경합니다.
     */
    public func setUUID(uuid: CBUUID) -> PlutoconEditor {
        changeUUID(uuid: uuid)
        return self
    }
    
    public func setUUID(uuidString: String) -> PlutoconEditor {
        
        guard let uuid = UUID(uuidString: uuidString) else {
            fatalError("Data is not UUID format.")
        }
        changeUUID(uuid: CBUUID(nsuuid: uuid))
        return self
    }
    
    fileprivate func changeUUID(uuid: CBUUID) {
        operationList.append((PlutoconUUID.UUID_CHARACTERISTIC, uuid.data))
    }
    
    /**
     * MAJOR / MINOR 는 0 이상 65535 이하 값이여야 변경합니다.
     *
     * BROADCASTING POWER 는 [-40, -30, -20, -16, -12, -8, -4, 0, 4] 중의 데이터여야만 변경가능합니다.
     *
     * BROADCASTING INTERVAL 는 100 이상 5000 이하여야 변경가능합니다.
     */
    public func setProperty(uuid: CBUUID, int value: Int) -> PlutoconEditor {
        if uuid == PlutoconUUID.MAJOR_CHARACTERISTIC || uuid == PlutoconUUID.MINOR_CHARACTERISTIC {
            guard value >= 0, value <= 65535 else {
                fatalError("The major/minor must be between 0 and 65535.")
            }
        }
        else if uuid == PlutoconUUID.TX_LEVEL_CHARACTERISTIC {
            guard let softwareVersion = self.plutoconConnection?.getSoftwareVersion(), softwareVersion.count > 1 else {
                return self
            }
            let splited = softwareVersion.subString(start: 1, end: softwareVersion.count).split(separator: ".")
            guard splited.count > 2,
                let major = Int(splited[0]),
                let minor = Int(splited[1]), major >= 1, minor >= 3
                 else {
                    return self
            }
            
            guard PlutoconEditor.TX_POWER_TEMPLATE.contains(value) else {
                fatalError("Tx Power can only input data in [-40, -30, -20, -16, -12, -8, -4, 0, 4]")
            }
        }
        else if uuid == PlutoconUUID.ADV_INTERVAL_CHARACTERISTIC {
            guard value >= 100, value <= 5000 else {
                fatalError("The adv interval must be between 100 and 5000.")
            }
        }
        
        var d = [UInt8](repeating: 0, count: 2)
        let v = UInt16(clamping: value)
        d[0] = UInt8(v >> 8)
        d[1] = UInt8(v & 0xFF)
        
        self.operationList.append((uuid,Data(bytes: d)))
        return self
    }
    
    /**
     * UUID 변경은 00000000-0000-0000-0000-000000000000 포맷과 일치해야 값을 변경합니다.
     * Data is not UUID format. (00000000-0000-0000-0000-000000000000)
     *
     * Device Name 변경은 1자리 이상 14자리 이하여야 변경합니다.
     * The device name must be between 1 and 14 characters long.
     */
    public func setProperty(uuid: CBUUID, string value: String) -> PlutoconEditor {
        if uuid == PlutoconUUID.UUID_CHARACTERISTIC {
            guard let uuid = UUID(uuidString: value) else {
                fatalError("Data is not UUID format. (00000000-0000-0000-0000-000000000000)")
            }
            self.changeUUID(uuid: CBUUID(nsuuid: uuid))
            return self
        }
        else if uuid == PlutoconUUID.DEVICE_NAME_CHARACTERISTIC {
            guard value.count >= 1, value.count <= 14 else {
                fatalError("The device name must be between 1 and 14 characters long.")
            }
        }
        
        self.operationList.append((uuid, Data(bytes: [UInt8](value.utf8))))
        return self
    }
    
    public func commit() {
        _ = execute()
    }
    
    public func execute() -> Bool {
        if let data = nextOperation() {
            delegate?.plutoconEditor(writeCharacteristic: data.0, data: data.1)
            return true
        }
        return false
    }
    
    // MARK: - Operation
    public func operationComplete(characteristic: CBCharacteristic, isLast: Bool) {
        self.operationCompletion?(characteristic, isLast)
    }
    
    public func nextOperation() -> (CBUUID, Data)? {
        if operationList.count > 0 {
            let data = operationList.remove(at: 0)
            return data
        }
        return nil
    }
}
