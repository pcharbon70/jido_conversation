import Config

config :jido_conversation, JidoConversation.EventSystem,
  partition_count: 8,
  runtime_partitions: 8
