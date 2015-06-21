//
//  SYNQueueTask.swift
//  SYNQueue
//
//  Created by John Hurliman on 6/18/15.
//  Copyright (c) 2015 Syntertainment. All rights reserved.
//

import Foundation

public typealias SYNTaskCallback = (SYNQueueTask) -> Void
public typealias JSONDictionary = [String: AnyObject?]

@objc
public class SYNQueueTask : NSOperation {
    static let MIN_RETRY_DELAY = 0.2
    static let MAX_RETRY_DELAY = 60.0
    
    public let queue: SYNQueue
    public let taskID: String
    public let taskType: String
    public let data: AnyObject?
    public let created: NSDate
    
    let dependencyStrs: [String]
    var started: NSDate?
    var retries: Int
    var _executing: Bool = false
    var _finished: Bool = false
    
    public override var name: String? { get { return taskID } set { } }
    public override var asynchronous: Bool { return true }
    
    public override var executing: Bool {
        get { return _executing }
        set {
            willChangeValueForKey("isExecuting")
            _executing = newValue
            didChangeValueForKey("isExecuting")
        }
    }
    public override var finished: Bool {
        get { return _finished }
        set {
            willChangeValueForKey("isFinished")
            _finished = newValue
            didChangeValueForKey("isFinished")
        }
    }
    
    public init(queue: SYNQueue, taskID: String, taskType: String,
        dependencyStrs: [String] = [], data: AnyObject? = nil,
        created: NSDate = NSDate(), started: NSDate? = nil, retries: Int = 0,
        queuePriority: NSOperationQueuePriority = .Normal,
        qualityOfService: NSQualityOfService = .Utility)
    {
        self.queue = queue
        self.taskID = taskID
        self.taskType = taskType
        self.dependencyStrs = dependencyStrs
        self.data = data
        self.created = created
        self.started = started
        self.retries = retries
        
        super.init()
        
        self.queuePriority = queuePriority
        self.qualityOfService = qualityOfService
    }
    
    public convenience init?(dictionary: JSONDictionary, queue: SYNQueue) {
        if  let taskID = dictionary["taskID"] as? String,
            let taskType = dictionary["taskType"] as? String,
            let dependencyStrs = dictionary["dependencies"] as? [String]? ?? [],
            let queuePriority = dictionary["queuePriority"] as? Int,
            let qualityOfService = dictionary["qualityOfService"] as? Int,
            let data: AnyObject? = dictionary["data"] as AnyObject??,
            let createdStr = dictionary["created"] as? String,
            let startedStr: String? = dictionary["started"] as? String ?? nil,
            let retries = dictionary["retries"] as? Int? ?? 0
        {
            let created = NSDate(dateString: createdStr) ?? NSDate()
            let started = (startedStr != nil) ? NSDate(dateString: startedStr!) : nil
            let priority = NSOperationQueuePriority(rawValue: queuePriority) ?? .Normal
            let qos = NSQualityOfService(rawValue: qualityOfService) ?? .Utility
            
            self.init(queue: queue, taskID: taskID, taskType: taskType,
                dependencyStrs: dependencyStrs, data: data, created: created,
                started: started, retries: retries, queuePriority: priority,
                qualityOfService: qos)
        } else {
            self.init(queue: queue, taskID: "", taskType: "")
            return nil
        }
    }
    
    public convenience init?(json: String, queue: SYNQueue) {
        if let dict = fromJSON(json) as? [String: AnyObject] {
            self.init(dictionary: dict, queue: queue)
        } else {
            self.init(queue: queue, taskID: "", taskType: "")
            return nil
        }
    }
    
    public func setupDependencies(allTasks: [SYNQueueTask]) {
        dependencyStrs.map {
            (taskID: String) -> Void in
            
            let found = allTasks.filter({ taskID == $0.name })
            if let task = found.first {
                self.addDependency(task)
            } else {
                let name = self.name ?? "(unknown)"
                self.queue.log(.Warning, "Discarding missing dependency \(taskID) from \(name)")
            }
        }
    }
    
    public func toDictionary() -> [String: AnyObject?] {
        var dict = [String: AnyObject?]()
        dict["taskID"] = self.taskID
        dict["taskType"] = self.taskType
        dict["dependencies"] = self.dependencyStrs
        dict["queuePriority"] = self.queuePriority.rawValue
        dict["qualityOfService"] = self.qualityOfService.rawValue
        dict["data"] = self.data
        dict["created"] = self.created.toISOString()
        dict["started"] = (self.started != nil) ? self.started!.toISOString() : nil
        dict["retries"] = self.retries
        
        return dict
    }
    
    public func toJSONString() -> String? {
        // Serialize this task to a dictionary
        let dict = toDictionary()
        
        // Convert the dictionary to an NSDictionary by replacing nil values
        // with NSNull
        var nsdict = NSMutableDictionary(capacity: dict.count)
        for (key, value) in dict {
            nsdict[key] = value ?? NSNull()
        }
        
        return toJSON(nsdict)
    }
    
    public override func start() {
        super.start()
        
        executing = true
        run()
    }
    
    public override func cancel() {
        super.cancel()
        
        queue.log(.Debug, "Canceled task \(taskID)")
        finished = true
    }
    
    func run() {
        if cancelled && !finished { finished = true }
        if finished { return }
        
        queue.runTask(self)
    }
    
    public func completed(error: NSError?) {
        // Check to make sure we're even executing, if not
        // just ignore the completed call
        if (!executing) {
            queue.log(.Debug, "Completion called on already completed task \(taskID)")
            return
        }
        
        if let error = error {
            queue.log(.Warning, "Task \(taskID) failed with error: \(error)")
            
            // Check if we've exceeded the max allowed retries
            if ++retries >= queue.maxRetries {
                queue.log(.Error, "Max retries exceeded for task \(taskID)")
                cancel()
                return
            }
            
            // Wait a bit (exponential backoff) and retry this task
            let exp = Double(min(queue.maxRetries ?? 0, retries))
            let seconds:NSTimeInterval = min(SYNQueueTask.MAX_RETRY_DELAY, SYNQueueTask.MIN_RETRY_DELAY * pow(2.0, exp - 1))
            
            queue.log(.Debug, "Waiting \(seconds) seconds to retry task \(taskID)")
            runInBackgroundAfter(seconds) { self.run() }
        } else {
            queue.log(.Debug, "Task \(taskID) completed")
            finished = true
        }
    }
}
