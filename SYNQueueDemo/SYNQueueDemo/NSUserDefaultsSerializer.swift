//
//  NSUserDefaultsSerializer.swift
//  SYNQueueDemo
//
//  Created by John Hurliman on 6/18/15.
//  Copyright (c) 2015 Syntertainment. All rights reserved.
//

import Foundation
import SYNQueue

class NSUserDefaultsSerializer : SYNQueueSerializationProvider {
    // MARK: - SYNQueueSerializationProvider Methods
    
    func serializeTask(task: SYNQueueTask, queueName: String) {
        if let serialized = task.toJSONString() {
            let defaults = NSUserDefaults.standardUserDefaults()
            var stringArray: [String]
            
            if let curStringArray = defaults.stringArrayForKey(queueName) as? [String] {
                stringArray = curStringArray
                stringArray.append(serialized)
            } else {
                stringArray = [serialized]
            }
            
            defaults.setValue(stringArray, forKey: queueName)
        } else {
            log(.Error, "Failed to serialize task \(task.taskID) in queue \(queueName)")
        }
    }
    
    func deserializeTasksInQueue(queue: SYNQueue) -> [SYNQueueTask] {
        let defaults = NSUserDefaults.standardUserDefaults()
        if  let queueName = queue.name,
            let stringArray = defaults.stringArrayForKey(queueName) as? [String]
        {
            return stringArray
                .map { return SYNQueueTask(json: $0, queue: queue) }
                .filter { return $0 != nil }
                .map { return $0! }
        }
        
        return []
    }
    
    func removeTask(taskID: String, queue: SYNQueue) {
        if let queueName = queue.name {
            var curArray: [SYNQueueTask] = deserializeTasksInQueue(queue)
            curArray = curArray.filter { return $0.taskID != taskID }
            
            let stringArray = curArray
                .map { return $0.toJSONString() }
                .filter { return $0 != nil }
                .map { return $0! }
            
            let defaults = NSUserDefaults.standardUserDefaults()
            defaults.setValue(stringArray, forKey: queueName)
        }
    }
}
