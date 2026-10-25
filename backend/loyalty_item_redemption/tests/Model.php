<?php

namespace Core;

class Model
{
    protected $db;

    public function __construct()
    {
        $this->db = Database::connect();
    }

    protected function lockClause(): string
    {
        return $this->db->getAttribute(\PDO::ATTR_DRIVER_NAME) === 'sqlite' ? '' : ' FOR UPDATE';
    }
}
