//
//  MasterViewController.swift
//  Bimbaj
//
//  Created by Bartosz Kopiński on 17/02/15.
//  Copyright (c) 2015 Bartosz Kopiński. All rights reserved.
//

import UIKit
import CoreData
import CoreLocation
import SwiftyJSON
import STHTTPRequest

class MasterViewController: UITableViewController, CLLocationManagerDelegate {
    var detailViewController: DetailViewController? = nil
    let locationManager = CLLocationManager()
    var stops: [[String: NSString]]
    var stopsDict: [String: [[String: NSString]]]
    var resultsArray: Array<JSON> = []
    var resultsDict: [String: [[String: String]]]
    var tableDict: [String: [[String: String]]] = Dictionary()
    let dateFormatter = NSDateFormatter()
    var allStops: [String: [String: String]]
    var stopsByDistance: [[String: NSString]]
    let charactersToRemove = NSCharacterSet.decimalDigitCharacterSet()
    var currentLocation: CLLocation?

    required init(coder aDecoder: NSCoder) {
        stopsDict = Dictionary(minimumCapacity: 1)
        stops = Array()
        resultsArray = Array(count: stops.count, repeatedValue: false)
        resultsDict = Dictionary()
        stopsByDistance = Array<Dictionary<String, NSString>>()
        allStops = Dictionary(minimumCapacity: 2000)

        super.init(coder: aDecoder)

        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        dateFormatter.locale = NSLocale(localeIdentifier: "PL_pl")

        let request = STHTTPRequest(URLString: "http://www.poznan.pl/mim/plan/map_service.html?mtype=pub_transport&co=cluster")

//        let path = NSBundle.mainBundle().pathForResource("przystanki-poznan", ofType: "json")
//        let jsonData = NSData(contentsOfFile: path!, options: .DataReadingMappedIfSafe, error: nil)!
        var error: NSError? = nil
        let result = request.startSynchronousWithError(&error)
        if(error != nil || result == nil) {
            println(error)
            return
        }

        let jsonData = result!.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)!

        for stop in JSON(data: jsonData)["features"].arrayValue {
            let id = stop["id"].stringValue
            let existingStop = allStops[id]
            var type = stop["properties"]["route_type"].stringValue == "0" ? "T" : "A"

            if (existingStop != nil) {
                allStops[id]!["type"]! += type
                continue
            }

            allStops[id] = [
                "id": id,
                "type": type,
                "name": stop["properties"]["stop_name"].stringValue,
                "longitude": stop["geometry"]["coordinates"][0].stringValue,
                "latitude": stop["geometry"]["coordinates"][1].stringValue,
            ]
        }

        println("Found \(allStops.count) stops")
    }

    func refresh(sender: AnyObject) {
        println("Refreshing...")
        fetchData()
        self.refreshControl!.endRefreshing()
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        if UIDevice.currentDevice().userInterfaceIdiom == .Pad {
            clearsSelectionOnViewWillAppear = false
            preferredContentSize = CGSize(width: 320.0, height: 600.0)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        locationManager.delegate = self
//        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.requestAlwaysAuthorization()
        locationManager.startUpdatingLocation()

        NSTimer.scheduledTimerWithTimeInterval(1, target: tableView, selector: Selector("reloadData"), userInfo: nil, repeats: true)
        NSTimer.scheduledTimerWithTimeInterval(30, target: self, selector: Selector("fetchData"), userInfo: nil, repeats: true)

        self.refreshControl = UIRefreshControl()
        self.refreshControl!.backgroundColor = UIColor(red: 253.0/255, green: 108.0/255, blue: 129.0/255, alpha: 0.0)
        self.refreshControl!.tintColor = UIColor.whiteColor();
        self.refreshControl!.addTarget(self, action: "refresh:", forControlEvents: UIControlEvents.ValueChanged)
    }

    func fetchData() {
        println("Fetching data");
        let request = STHTTPRequest(URLString: "http://www.peka.poznan.pl/vm/method.vm?ts=1424698759183")
        var result: NSString?
        var error: NSError? = nil
        var data: NSData?

        println("Found \(stopsDict.count) general stops")

        for (generalStop, stops) in stopsDict {
            resultsDict[generalStop] = Array()

            for stop in stops {
                let stopId = stop["id"] as! String
                request.POSTDictionary = ["method": "getTimes", "p0": ["symbol": stopId]]
                error = nil
                result = request.startSynchronousWithError(&error)
                if (error != nil) {
                    println("Request error \(error) for \(stopId)")
                    continue
                }
//                println(result)
                data = result!.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)
                let json = JSON(data: data!)["success"]
                let rides = json["times"].arrayValue
                println("Received \(rides.count) rides for \(stop)")

                for ride in rides {
                    resultsDict[generalStop]!.append([
                        "line": ride["line"].stringValue,
                        "minutes": ride["minutes"].stringValue,
                        "direction": ride["direction"].stringValue,
                        "departure": ride["departure"].stringValue
                    ])
                }
            }
            println("Results count: \(resultsDict.count)");

            resultsDict[generalStop]!.sort({ $0["minutes"]!.toInt() < $1["minutes"]!.toInt() })
        }
    }

    func locationManager(manager: CLLocationManager!, didUpdateLocations locations: [AnyObject]!) {
        if (currentLocation != nil && manager.location.distanceFromLocation(currentLocation) <= 10.0) {
            // Not moved
            return
        }
        println("Moved by \(manager.location.distanceFromLocation(currentLocation))")
        currentLocation = manager.location
        println("Received new location: \(currentLocation?.coordinate.latitude) \(currentLocation?.coordinate.longitude)")

        stopsByDistance = []

        for (id, stop) in allStops {
            let latitude = (stop["latitude"]! as NSString).doubleValue
            let longitude = (stop["longitude"]! as NSString).doubleValue
            let stopPosition = CLLocation(latitude: latitude, longitude: longitude)
            let distance = currentLocation!.distanceFromLocation(stopPosition)

//            println("Stop position: \(latitude) \(longitude) Distance: \(distance)")

            stopsByDistance.append([
                "id": id,
                "type": stop["type"]!,
                "name": stop["name"]!,
                "distance": distance.description
            ])
        }

        stopsByDistance.sort({ $0["distance"]!.doubleValue < $1["distance"]!.doubleValue })

        println("Stops by distance count: \(stopsByDistance.count)")
        println("Stops count: \(stops)")
        println("Closest stop: \(stopsByDistance[0])")

        if (!stops.isEmpty && stops[0]["name"] == stopsByDistance[0]["name"]) {
            println("Closest stop not changed")
            return;
        }

        self.stops = Array(stopsByDistance[0...4])

        stopsDict = Dictionary(minimumCapacity: 1)

        var generalStopId: NSString = ""
        for stop in stops {
            generalStopId = ((stop["id"] as! String).componentsSeparatedByCharactersInSet(charactersToRemove) as NSArray).componentsJoinedByString("")

            if (stopsDict[generalStopId as String] == nil) {
                stopsDict[generalStopId as String] = []
            }
            println("Adding \(stop) to stopsDict")
            stopsDict[generalStopId as String]?.append(stop)
        }

        fetchData()
    }

    // MARK: - Table View

    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        self.tableDict = resultsDict
        return tableDict.count
    }

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let stop: NSString = tableDict.keys.array[section]
        return tableDict[stop as String]!.count
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath) as! UITableViewCell
        configureCell(cell, atIndexPath: indexPath)
        return cell
    }

    override func tableView(tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let cell = tableView.dequeueReusableCellWithIdentifier("Header") as! UITableViewCell
        configureHeader(cell, atSection: section)
        return cell
    }

    func configureHeader(cell: UITableViewCell, atSection section: Int) {
        let stopId = tableDict.keys.array[section]
        let stops = stopsDict[stopId]
        if (stops == nil) {
            return
        }

        let stopName = stops![0]["name"]!
        var stopType = stops![0]["type"]!
        let stopDistance = Int(stops![0]["distance"]!.doubleValue)
        cell.textLabel!.text = "\(stopName)"
        cell.detailTextLabel!.text = "\(stopDistance)m"

        stopType = stopType.stringByReplacingOccurrencesOfString("T", withString: String(format: " %C", 0xE01E))
        stopType = stopType.stringByReplacingOccurrencesOfString("A", withString: String(format: " %C", 0xE159))

        let typeLabel = cell.contentView.subviews.last as! UILabel
        typeLabel.text = stopType as String
        cell.layer.shadowColor = UIColor.whiteColor().CGColor;

        cell.layer.shadowOpacity = 1.0;
        cell.layer.shadowRadius = 0;
        cell.layer.shadowOffset = CGSizeMake(0.0, 0.7);

    }

    override func tableView(tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let cell = tableView.dequeueReusableCellWithIdentifier("Footer") as! UITableViewCell
        return cell
    }

    override func tableView(tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 10
    }

    override func tableView(tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 45
    }

    override func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        return 30
    }

    func configureCell(cell: UITableViewCell, atIndexPath indexPath: NSIndexPath) {
        let stop: NSString = tableDict.keys.array[indexPath.section]
        let ride = tableDict[stop as String]![indexPath.row]

        let line = ride["line"]!.stringByPaddingToLength(3, withString: " ", startingAtIndex: 0)

        let departure = dateFormatter.dateFromString(ride["departure"]!.removeCharsFromEnd(5))!
//        let date = NSDate().timeIntervalSinceDate(departure)
//        println("\(departure) \(ride)")

        let date = departure.timeIntervalSinceNow

        let totalSeconds = date as Double
        let seconds = totalSeconds % 60
        let minutes = totalSeconds/60

        let timer = secondsToHoursMinutesSeconds(totalSeconds)

        cell.textLabel!.text = line + " → " + ride["direction"]!

        if (totalSeconds <= 0.0) {
            cell.detailTextLabel!.text = seconds % 2 == 0.0 ? "-" : ""
        } else {
            cell.detailTextLabel!.text = secondsToHoursMinutesSeconds(totalSeconds)
        }

        if (totalSeconds < 60) {
            cell.backgroundColor = UIColor(red: CGFloat((83)/255.0), green: CGFloat((140+totalSeconds)/255.0), blue: CGFloat((253)/255.0), alpha: 1.0)
        } else {
            cell.backgroundColor = UIColor(red: 83/255.0, green: 200/255.0, blue: 1.0, alpha: 1.0)
        }

        if (totalSeconds < -10.0) {
            fetchData()
        }
    }

    func secondsToHoursMinutesSeconds (seconds: Double) -> String {
        let (hr,  minf) = modf (seconds / 3600)
        let (min, secf) = modf (60 * minf)
        return String(format: "%02.0f:%02.0f:%02.0f", hr, min, secf * 60)
    }

}

