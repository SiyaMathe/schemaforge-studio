// =============================================================================
// SchemaForge Studio — Khulisa Commerce
// NoSQL (MongoDB) — Product Reviews & Event Store
// Demonstrates: Collection design, compound indexes, aggregation pipelines,
//               $facet, $lookup (join), $bucket, $geoNear, text search,
//               $graphLookup (recursive), schema validation, transactions
// Run in: MongoDB Shell (mongosh) or MongoDB Compass Shell tab
// =============================================================================

// ── 1. Create database ────────────────────────────────────────────────────────
use khulisa_nosql;

// ── 2. Schema validation — enforce structure at the DB level ─────────────────
// MongoDB is schemaless by default, but we can add JSON Schema validation
db.createCollection("reviews", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["product_id", "customer_id", "rating", "created_at"],
      properties: {
        product_id:   { bsonType: "int",    description: "SQL ProductID FK" },
        customer_id:  { bsonType: "int",    description: "SQL CustomerID FK" },
        rating:       { bsonType: "int",    minimum: 1, maximum: 5 },
        title:        { bsonType: "string", maxLength: 200 },
        body:         { bsonType: "string", maxLength: 2000 },
        is_verified:  { bsonType: "bool" },
        is_approved:  { bsonType: "bool" },
        created_at:   { bsonType: "date" },
        helpful_votes: { bsonType: "int",  minimum: 0 }
      }
    }
  },
  validationAction: "error"
});

db.createCollection("product_events");    // behavioural events (views, clicks, adds-to-cart)
db.createCollection("vendor_locations");  // geo-enabled vendor pickup points

// ── 3. Indexes ────────────────────────────────────────────────────────────────

// Reviews: compound index for product page (approved reviews, newest first)
db.reviews.createIndex(
  { product_id: 1, is_approved: 1, created_at: -1 },
  { name: "ix_product_approved_date" }
);

// Reviews: text search on title + body
db.reviews.createIndex(
  { title: "text", body: "text" },
  { name: "ix_text_search", weights: { title: 3, body: 1 } }
);

// Reviews: customer review history
db.reviews.createIndex(
  { customer_id: 1, created_at: -1 },
  { name: "ix_customer_date" }
);

// Reviews: unique constraint — one review per customer per product
db.reviews.createIndex(
  { product_id: 1, customer_id: 1 },
  { unique: true, name: "uq_product_customer" }
);

// Product events: TTL index — auto-expire raw events after 90 days
db.product_events.createIndex(
  { created_at: 1 },
  { expireAfterSeconds: 7776000, name: "ttl_events" }
);

// Product events: query by customer + product for funnel analysis
db.product_events.createIndex(
  { customer_id: 1, product_id: 1, event_type: 1, created_at: -1 },
  { name: "ix_customer_product_event" }
);

// Vendor locations: 2dsphere for geo queries
db.vendor_locations.createIndex(
  { location: "2dsphere" },
  { name: "ix_geospatial" }
);

// ── 4. Seed reviews ───────────────────────────────────────────────────────────
db.reviews.insertMany([
  {
    product_id:    1,
    customer_id:   1,
    rating:        5,
    title:         "Absolutely love these!",
    body:          "Best running shoes I have owned. Great cushioning, true to size. Wore them on a 10km run after one day of breaking in.",
    is_verified:   true,
    is_approved:   true,
    helpful_votes: 14,
    tags:          ["comfortable", "true-to-size", "durable"],
    created_at:    ISODate("2024-01-20T10:30:00Z")
  },
  {
    product_id:    1,
    customer_id:   2,
    rating:        4,
    title:         "Great shoe, delivered fast",
    body:          "Very happy with the quality. Delivery from Joburg to Durban took two days. Minus one star because the box was slightly damaged.",
    is_verified:   true,
    is_approved:   true,
    helpful_votes: 7,
    tags:          ["fast-delivery", "good-quality"],
    created_at:    ISODate("2024-01-22T14:15:00Z")
  },
  {
    product_id:    2,
    customer_id:   1,
    rating:        3,
    title:         "Decent but runs small",
    body:          "The fabric quality is good but I had to exchange for a size up. Size guide on the website should be updated.",
    is_verified:   true,
    is_approved:   true,
    helpful_votes: 22,
    tags:          ["sizing-issue", "good-fabric"],
    created_at:    ISODate("2024-01-25T09:00:00Z")
  },
  {
    product_id:    1,
    customer_id:   3,
    rating:        2,
    title:         "Disappointed",
    body:          "Sole started separating after 3 weeks. Contacted support — still waiting for a response.",
    is_verified:   true,
    is_approved:   false,  // pending moderation
    helpful_votes: 0,
    tags:          ["defective", "poor-support"],
    created_at:    ISODate("2024-02-01T16:45:00Z")
  }
]);

// ── 5. Seed product events ────────────────────────────────────────────────────
db.product_events.insertMany([
  { customer_id: 1, product_id: 1, event_type: "VIEW",         session_id: "sess_abc", created_at: ISODate("2024-01-19T09:00:00Z") },
  { customer_id: 1, product_id: 1, event_type: "ADD_TO_CART",  session_id: "sess_abc", created_at: ISODate("2024-01-19T09:05:00Z") },
  { customer_id: 1, product_id: 1, event_type: "PURCHASE",     session_id: "sess_abc", created_at: ISODate("2024-01-19T09:12:00Z") },
  { customer_id: 2, product_id: 1, event_type: "VIEW",         session_id: "sess_def", created_at: ISODate("2024-01-20T11:00:00Z") },
  { customer_id: 2, product_id: 1, event_type: "VIEW",         session_id: "sess_def", created_at: ISODate("2024-01-20T11:02:00Z") },
  { customer_id: 2, product_id: 2, event_type: "VIEW",         session_id: "sess_def", created_at: ISODate("2024-01-20T11:05:00Z") },
  { customer_id: 2, product_id: 1, event_type: "ADD_TO_CART",  session_id: "sess_def", created_at: ISODate("2024-01-20T11:10:00Z") },
  { customer_id: 2, product_id: 1, event_type: "PURCHASE",     session_id: "sess_def", created_at: ISODate("2024-01-20T11:15:00Z") },
  { customer_id: 3, product_id: 1, event_type: "VIEW",         session_id: "sess_ghi", created_at: ISODate("2024-01-28T14:00:00Z") },
  { customer_id: 3, product_id: 1, event_type: "ADD_TO_CART",  session_id: "sess_ghi", created_at: ISODate("2024-01-28T14:03:00Z") },
  { customer_id: 3, product_id: 1, event_type: "REMOVE_FROM_CART", session_id: "sess_ghi", created_at: ISODate("2024-01-28T14:10:00Z") }
  // customer 3 abandoned cart — no PURCHASE event
]);

// ── 6. Seed vendor locations ──────────────────────────────────────────────────
db.vendor_locations.insertMany([
  {
    vendor_id:   1,
    vendor_name: "SoleStore",
    location: { type: "Point", coordinates: [28.0567, -26.1076] },  // Sandton
    address:  "Shop 12, Sandton City Mall, Johannesburg",
    pickup_available: true,
    hours: "Mon-Sat 09:00-18:00"
  },
  {
    vendor_id:   1,
    vendor_name: "SoleStore",
    location: { type: "Point", coordinates: [18.4232, -33.9249] },  // Cape Town CBD
    address:  "44 Long Street, Cape Town",
    pickup_available: true,
    hours: "Mon-Fri 08:30-17:30, Sat 09:00-14:00"
  },
  {
    vendor_id:   2,
    vendor_name: "ActiveGear",
    location: { type: "Point", coordinates: [31.0218, -29.8587] },  // Durban
    address:  "Pavilion Shopping Centre, Westville, Durban",
    pickup_available: true,
    hours: "Mon-Sun 09:00-19:00"
  }
]);

// ── 7. Aggregation Pipeline 1: Product review summary ────────────────────────
// Groups, counts, averages ratings, builds sentiment distribution
db.reviews.aggregate([
  // Stage 1: only approved reviews
  { $match: { is_approved: true } },

  // Stage 2: group by product, compute stats
  {
    $group: {
      _id:            "$product_id",
      total_reviews:  { $sum: 1 },
      avg_rating:     { $avg: "$rating" },
      total_helpful:  { $sum: "$helpful_votes" },
      // Rating distribution
      five_star:  { $sum: { $cond: [{ $eq: ["$rating", 5] }, 1, 0] } },
      four_star:  { $sum: { $cond: [{ $eq: ["$rating", 4] }, 1, 0] } },
      three_star: { $sum: { $cond: [{ $eq: ["$rating", 3] }, 1, 0] } },
      two_star:   { $sum: { $cond: [{ $eq: ["$rating", 2] }, 1, 0] } },
      one_star:   { $sum: { $cond: [{ $eq: ["$rating", 1] }, 1, 0] } },
      // Collect all tags
      all_tags:   { $push: "$tags" }
    }
  },

  // Stage 3: add computed fields
  {
    $addFields: {
      avg_rating:     { $round: ["$avg_rating", 1] },
      positive_rate:  {
        $round: [{
          $multiply: [{
            $divide: [{ $add: ["$five_star", "$four_star"] }, "$total_reviews"]
          }, 100]
        }, 1]
      },
      // Flatten nested arrays of tags
      flattened_tags: {
        $reduce: {
          input: "$all_tags",
          initialValue: [],
          in: { $concatArrays: ["$$value", "$$this"] }
        }
      }
    }
  },

  // Stage 4: sort by review volume
  { $sort: { total_reviews: -1 } },

  // Stage 5: clean output
  {
    $project: {
      _id: 0,
      product_id:    "$_id",
      total_reviews: 1,
      avg_rating:    1,
      positive_rate: 1,
      total_helpful: 1,
      rating_distribution: {
        five:  "$five_star",
        four:  "$four_star",
        three: "$three_star",
        two:   "$two_star",
        one:   "$one_star"
      }
    }
  }
]);

// ── 8. Aggregation Pipeline 2: $facet — multi-dimensional query in one pass ──
// Returns review stats + rating distribution + tag frequency simultaneously
db.reviews.aggregate([
  { $match: { is_approved: true } },
  {
    $facet: {
      // Facet 1: Overall stats
      overall: [
        {
          $group: {
            _id:          null,
            total:        { $sum: 1 },
            avg_rating:   { $avg: "$rating" },
            most_helpful: { $max: "$helpful_votes" }
          }
        },
        { $project: { _id: 0 } }
      ],

      // Facet 2: Rating breakdown (bucket by star)
      by_rating: [
        { $group: { _id: "$rating", count: { $sum: 1 } } },
        { $sort: { _id: -1 } },
        { $project: { _id: 0, stars: "$_id", count: 1 } }
      ],

      // Facet 3: Recent reviews (last 30 days)
      recent: [
        {
          $match: {
            created_at: { $gte: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000) }
          }
        },
        { $count: "count_last_30_days" }
      ],

      // Facet 4: Value histogram — bucket reviews by helpful votes
      helpfulness_buckets: [
        {
          $bucket: {
            groupBy:    "$helpful_votes",
            boundaries: [0, 5, 10, 25, 50, 100],
            default:    "100+",
            output:     { count: { $sum: 1 }, avg_rating: { $avg: "$rating" } }
          }
        }
      ]
    }
  }
]);

// ── 9. Aggregation Pipeline 3: $lookup — join reviews with events ─────────────
// Find reviews where the customer had viewed the product multiple times before buying
// (demonstrates MongoDB's equivalent of a SQL JOIN)
db.reviews.aggregate([
  { $match: { is_approved: true, rating: { $gte: 4 } } },

  // Join to product_events to get this customer's event history for this product
  {
    $lookup: {
      from:         "product_events",
      let:          { pid: "$product_id", cid: "$customer_id" },
      pipeline: [
        {
          $match: {
            $expr: {
              $and: [
                { $eq: ["$product_id",  "$$pid"] },
                { $eq: ["$customer_id", "$$cid"] }
              ]
            }
          }
        },
        { $sort:  { created_at: 1 } },
        {
          $group: {
            _id:         null,
            view_count:  { $sum: { $cond: [{ $eq: ["$event_type", "VIEW"] }, 1, 0] } },
            first_view:  { $first: "$created_at" },
            purchased_at: {
              $max: {
                $cond: [{ $eq: ["$event_type", "PURCHASE"] }, "$created_at", null]
              }
            }
          }
        }
      ],
      as: "event_summary"
    }
  },

  // Unwind (flatten the joined array — similar to INNER JOIN behaviour)
  { $unwind: { path: "$event_summary", preserveNullAndEmptyArrays: false } },

  // Add days between first view and purchase
  {
    $addFields: {
      days_to_purchase: {
        $divide: [
          { $subtract: ["$event_summary.purchased_at", "$event_summary.first_view"] },
          86400000  // ms in a day
        ]
      }
    }
  },

  {
    $project: {
      product_id:   1,
      customer_id:  1,
      rating:       1,
      title:        1,
      view_count:   "$event_summary.view_count",
      days_to_purchase: { $round: ["$days_to_purchase", 1] }
    }
  },

  { $sort: { view_count: -1 } }
]);

// ── 10. Funnel Analysis: VIEW → ADD_TO_CART → PURCHASE conversion ─────────────
db.product_events.aggregate([
  { $match: { product_id: 1 } },

  // Group by customer to get their max funnel stage
  {
    $group: {
      _id: "$customer_id",
      events: { $addToSet: "$event_type" }
    }
  },

  // Classify each customer's funnel stage
  {
    $addFields: {
      funnel_stage: {
        $switch: {
          branches: [
            { case: { $in: ["PURCHASE",      "$events"] }, then: "PURCHASED" },
            { case: { $in: ["ADD_TO_CART",   "$events"] }, then: "ADDED_TO_CART" },
            { case: { $in: ["VIEW",          "$events"] }, then: "VIEWED" }
          ],
          default: "UNKNOWN"
        }
      }
    }
  },

  // Count per stage
  { $group: { _id: "$funnel_stage", customers: { $sum: 1 } } },

  // Sort by funnel order
  {
    $addFields: {
      sort_order: {
        $switch: {
          branches: [
            { case: { $eq: ["$_id", "VIEWED"]       }, then: 1 },
            { case: { $eq: ["$_id", "ADDED_TO_CART"] }, then: 2 },
            { case: { $eq: ["$_id", "PURCHASED"]    }, then: 3 }
          ],
          default: 4
        }
      }
    }
  },
  { $sort: { sort_order: 1 } },
  { $project: { _id: 0, stage: "$_id", customers: 1 } }
]);

// ── 11. $geoNear — find vendor pickup points within 15km of a location ─────────
db.vendor_locations.aggregate([
  {
    $geoNear: {
      near: {
        type:        "Point",
        coordinates: [28.0473, -26.2041]   // Johannesburg CBD
      },
      distanceField:  "distance_meters",
      maxDistance:    15000,               // 15km radius
      spherical:      true,
      query:          { pickup_available: true }
    }
  },
  {
    $project: {
      vendor_name:      1,
      address:          1,
      hours:            1,
      pickup_available: 1,
      distance_km:      { $round: [{ $divide: ["$distance_meters", 1000] }, 2] }
    }
  },
  { $sort: { distance_meters: 1 } }
]);

// ── 12. Text search — find reviews mentioning sizing ─────────────────────────
db.reviews.find(
  {
    $text:       { $search: "size sizing small large fit" },
    is_approved: true
  },
  {
    score:      { $meta: "textScore" },
    product_id: 1,
    rating:     1,
    title:      1,
    body:       1
  }
).sort({ score: { $meta: "textScore" } });

// ── 13. Basic queries — mirrors the DBAS exam NoSQL questions ─────────────────

// Q4.3 equivalent: Get a list of all reviews in the collection
db.reviews.find({}).sort({ created_at: -1 });

// Q4.4 equivalent: Query all reviews where rating is less than or equal to 3
db.reviews.find(
  {
    rating:      { $lte: 3 },
    is_approved: true
  },
  {
    product_id:  1,
    customer_id: 1,
    rating:      1,
    title:       1,
    created_at:  1
  }
).sort({ rating: 1, created_at: -1 });

// Count reviews by product
db.reviews.aggregate([
  { $group: { _id: "$product_id", count: { $sum: 1 }, avg: { $avg: "$rating" } } },
  { $sort:  { count: -1 } }
]);

print("All MongoDB queries executed successfully.");
