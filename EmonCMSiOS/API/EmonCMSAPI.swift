//
//  EmonCMSAPI.swift
//  EmonCMSiOS
//
//  Created by Matt Galloway on 12/09/2016.
//  Copyright © 2016 Matt Galloway. All rights reserved.
//

import Foundation

import RxSwift
import Alamofire
import Unbox

class EmonCMSAPI {

  private let requestProvider: HTTPRequestProvider

  private enum EmonCMSAPIError: Error {
    case FailedToCreateURL
    case RequestFailed
    case InvalidResponse
  }

  init(requestProvider: HTTPRequestProvider) {
    self.requestProvider = requestProvider
  }

  private class func buildURL(_ account: Account, path: String, queryItems: [String:String] = [:]) throws -> URL {
    guard var urlBuilder = URLComponents(string: account.url) else {
      throw EmonCMSAPIError.FailedToCreateURL
    }

    urlBuilder.path = "/feed/" + path + ".json"

    var allQueryItems = queryItems
    allQueryItems["apikey"] = account.apikey
    urlBuilder.queryItems = allQueryItems.map() { URLQueryItem(name: $0, value: $1) }

    if let url = urlBuilder.url {
      return url
    } else {
      throw EmonCMSAPIError.FailedToCreateURL
    }
  }

  private func request(_ account: Account, path: String, queryItems: [String:String] = [:]) -> Observable<Data> {
    let url: URL
    do {
      url = try EmonCMSAPI.buildURL(account, path: path, queryItems: queryItems)
    } catch {
      return Observable.error(error)
    }

    return self.requestProvider.request(url: url)
  }

  func feedList(_ account: Account) -> Observable<[Feed]> {
    return self.request(account, path: "list").map { resultData -> [Feed] in
      do {
        let feeds: [Feed] = try Unbox(data: resultData)
        return feeds
      } catch {
        throw EmonCMSAPIError.InvalidResponse
      }
    }
  }

  func feedFields(_ account: Account, id: String) -> Observable<Feed> {
    let queryItems = [
      "id": id
    ]

    return self.request(account, path: "aget", queryItems: queryItems).map { resultData -> Feed in
      do {
        let feed: Feed = try Unbox(data: resultData)
        return feed
      } catch {
        throw EmonCMSAPIError.InvalidResponse
      }
    }
  }

  func feedField(_ account: Account, id: String, fieldName: String) -> Observable<String> {
    let queryItems = [
      "id": id,
      "field": fieldName
    ]

    return self.request(account, path: "get", queryItems: queryItems).map { resultData -> String in
      guard let json = try? JSONSerialization.jsonObject(with: resultData, options: [.allowFragments]),
        let value = json as? String else {
          throw EmonCMSAPIError.InvalidResponse
      }

      return value
    }
  }

  func feedData(_ account: Account, id: String, at startTime: Date, until endTime: Date, interval: Int) -> Observable<[FeedDataPoint]> {
    let queryItems = [
      "id": id,
      "start": "\(Int(startTime.timeIntervalSince1970 * 1000))",
      "end": "\(Int(endTime.timeIntervalSince1970 * 1000))",
      "interval": "\(interval)"
    ]

    return self.request(account, path: "data", queryItems: queryItems).map { resultData -> [FeedDataPoint] in
      guard let json = try? JSONSerialization.jsonObject(with: resultData),
        let dataPoints = json as? [Any] else {
          throw EmonCMSAPIError.InvalidResponse
      }

      var feedDataPoints: [FeedDataPoint] = []
      for dataPoint in dataPoints {
        guard let typedDataPoint = dataPoint as? [Double] else {
          continue
        }
        if let feedDataPoint = FeedDataPoint.from(dataArray: typedDataPoint) {
          feedDataPoints.append(feedDataPoint)
        }
      }
      return feedDataPoints
    }
  }

  func feedValue(_ account: Account, id: String) -> Observable<Double> {
    let queryItems = [
      "id": id
    ]

    return self.request(account, path: "value", queryItems: queryItems).map { resultData -> Double in
      guard let json = try? JSONSerialization.jsonObject(with: resultData, options: [.allowFragments]),
        let string = json as? String,
        let value = Double(string) else {
          throw EmonCMSAPIError.InvalidResponse
      }

      return value
    }
  }

  func feedValue(_ account: Account, ids: [String]) -> Observable<[String:Double]> {
    let queryItems = [
      "ids": ids.joined(separator: ",")
    ]

    return self.request(account, path: "fetch", queryItems: queryItems).map { resultData -> [String:Double] in
      guard let json = try? JSONSerialization.jsonObject(with: resultData),
        let array = json as? [Any] else {
          throw EmonCMSAPIError.InvalidResponse
      }

      var results: [String:Double] = [:]
      for (id, valueAny) in zip(ids, array) {
        guard let valueString = valueAny as? String,
          let value = Double(valueString) else {
            throw EmonCMSAPIError.InvalidResponse
        }

        results[id] = value
      }
      return results
    }
  }

}
