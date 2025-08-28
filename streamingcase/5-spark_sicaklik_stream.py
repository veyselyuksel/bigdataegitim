from pyspark.sql import SparkSession
from pyspark.sql.functions import from_json, col, window, avg, max, min, expr
from pyspark.sql.types import StructType, StringType, DoubleType, TimestampType

spark = SparkSession.builder \
    .appName("TurkiyeSicaklikStreaming") \
    .master("spark://spark-master01:7077") \
    .getOrCreate()

spark.sparkContext.setLogLevel("WARN")

schema = StructType() \
    .add("city", StringType()) \
    .add("temperature_f", DoubleType()) \
    .add("timestamp", StringType())

# Kafka’dan oku
df = spark.readStream \
    .format("kafka") \
    .option("kafka.bootstrap.servers", "spark-master01:9092") \
    .option("subscribe", "turkiye_sicaklik") \
    .option("startingOffsets", "latest") \
    .load()

# JSON parse
parsed = df.selectExpr("CAST(value AS STRING)") \
    .select(from_json(col("value"), schema).alias("data")) \
    .select("data.*")

# String → Timestamp
parsed = parsed.withColumn("ts", col("timestamp").cast(TimestampType()))

# Fahrenheit → Celsius
parsed = parsed.withColumn("temperature_c",
    expr("(temperature_f - 32) * 5/9"))


tumbling = parsed.groupBy(
    window(col("ts"), "30 seconds"),
    col("city")
).agg(
    avg("temperature_c").alias("avg_temp_c")
)

tumbling_out = tumbling.selectExpr(
    "window.start as window_start",
    "window.end as window_end",
    "city", "avg_temp_c"
)

tumbling_query = tumbling_out.writeStream \
    .foreachBatch(lambda df, epochId: df.write \
        .format("jdbc")
        .option("url", "jdbc:postgresql://spark-master01:5432/streamdb")
        .option("dbtable", "temperature_tumbling")
        .option("user", "streamuser")
        .option("password", "streampass")
        .option("driver", "org.postgresql.Driver")
        .mode("append")
        .save()) \
    .outputMode("update") \
    .start()



sliding = parsed.groupBy(
    window(col("ts"), "30 seconds", "10 seconds"),
    col("city")
).agg(
    max("temperature_c").alias("max_temp_c"),
    min("temperature_c").alias("min_temp_c")
)

sliding_out = sliding.selectExpr(
    "window.start as window_start",
    "window.end as window_end",
    "city", "max_temp_c", "min_temp_c"
)

sliding_query = sliding_out.writeStream \
    .foreachBatch(lambda df, epochId: df.write \
        .format("jdbc")
        .option("url", "jdbc:postgresql://spark-master01:5432/streamdb")
        .option("dbtable", "temperature_sliding")
        .option("user", "streamuser")
        .option("password", "streampass")
        .option("driver", "org.postgresql.Driver")
        .mode("append")
        .save()) \
    .outputMode("update") \
    .start()

spark.streams.awaitAnyTermination()
